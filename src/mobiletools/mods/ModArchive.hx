package mobiletools.mods;

import haxe.io.Bytes;

#if sys
import sys.FileSystem;
import sys.io.File;
import sys.io.FileInput;
import sys.io.FileSeek;
#end

/**
 * Reads a `.zip` file one entry at a time, for `ModManager.install()`.
 *
 * `haxe.zip.Reader` decompresses everything up front and trusts the sizes it finds, which a hostile archive can
 * use to fill the memory of a phone. This reads the central directory instead, so every size is known (and can be
 * refused) before anything is decompressed, and checks each entry against its CRC.
 *
 * Stored and deflated entries are supported. Encrypted and ZIP64 archives are refused.
 */
@:noCompletion
class ModArchive
{
	private static inline var END_SIGNATURE:Int = 0x06054b50;
	private static inline var CENTRAL_SIGNATURE:Int = 0x02014b50;
	private static inline var LOCAL_SIGNATURE:Int = 0x04034b50;

	/** End of central directory record without comment, plus the longest comment allowed. */
	private static inline var MAX_END_SEARCH:Int = 22 + 0xffff;

	public final entries:Array<ArchiveEntry> = [];

	#if sys
	private var input:FileInput;
	#end

	/** @throws String when the file can't be read or isn't a zip this can handle. */
	public static function open(path:String):ModArchive
	{
		#if sys
		return new ModArchive(path);
		#else
		throw 'Archives cannot be read on this target';
		#end
	}

	private function new(path:String)
	{
		#if sys
		var size:Int;

		try
		{
			size = FileSystem.stat(path).size;
			input = File.read(path, true);
		}
		catch (e:Dynamic)
		{
			throw 'Could not open the archive';
		}

		try
		{
			readCentralDirectory(size);
		}
		catch (e:Dynamic)
		{
			close();
			throw e;
		}
		#end
	}

	public function get(name:String):Null<ArchiveEntry>
	{
		for (entry in entries)
		{
			if (entry.name == name)
				return entry;
		}

		return null;
	}

	/**
	 * The decompressed contents of `entry`.
	 *
	 * @throws String when the data is damaged or doesn't match the sizes and CRC the directory promised.
	 */
	public function read(entry:ArchiveEntry):Bytes
	{
		#if sys
		input.seek(entry.offset, SeekBegin);
		var header = readBytes(30);

		if (header.getInt32(0) != LOCAL_SIGNATURE)
			throw 'Damaged archive: bad header for ${entry.name}';

		// The local copy of the name and extra field can differ in length from the central one.
		input.seek(entry.offset + 30 + header.getUInt16(26) + header.getUInt16(28), SeekBegin);

		var compressed = readBytes(entry.compressedSize);
		var data = entry.method == 0 ? compressed : inflate(compressed, entry.size, entry.name);

		if (data.length != entry.size || haxe.crypto.Crc32.make(data) != entry.crc)
			throw 'Damaged archive: ${entry.name} does not match its checksum';

		return data;
		#else
		throw 'Archives cannot be read on this target';
		#end
	}

	public function close():Void
	{
		#if sys
		if (input != null)
		{
			input.close();
			input = null;
		}
		#end
	}

	#if sys
	private function readCentralDirectory(fileSize:Int):Void
	{
		var tailLength = fileSize < MAX_END_SEARCH ? fileSize : MAX_END_SEARCH;

		if (tailLength < 22)
			throw 'Not a zip file';

		input.seek(fileSize - tailLength, SeekBegin);
		var tail = readBytes(tailLength);
		var end = tailLength - 22;

		while (end >= 0 && tail.getInt32(end) != END_SIGNATURE)
			end--;

		if (end < 0)
			throw 'Not a zip file';

		var count = tail.getUInt16(end + 10);
		var directorySize = tail.getInt32(end + 12);
		var directoryOffset = tail.getInt32(end + 16);

		// 0xffff / 0xffffffff mean the real values are in a ZIP64 record. Such archives are bigger than any mod should be.
		if (count == 0xffff || directorySize < 0 || directoryOffset < 0 || directoryOffset + directorySize > fileSize)
			throw 'Unsupported or damaged zip file';

		input.seek(directoryOffset, SeekBegin);
		var directory = readBytes(directorySize);
		var position = 0;

		for (_ in 0...count)
		{
			if (position + 46 > directory.length || directory.getInt32(position) != CENTRAL_SIGNATURE)
				throw 'Damaged archive: bad central directory';

			var flags = directory.getUInt16(position + 8);
			var method = directory.getUInt16(position + 10);
			var nameLength = directory.getUInt16(position + 28);
			var extraLength = directory.getUInt16(position + 30);
			var commentLength = directory.getUInt16(position + 32);
			var attributes = directory.getInt32(position + 38);

			if (position + 46 + nameLength > directory.length)
				throw 'Damaged archive: bad central directory';

			var name = directory.getString(position + 46, nameLength).split('\\').join('/');

			var entry:ArchiveEntry = {
				name: name,
				method: method,
				crc: directory.getInt32(position + 16),
				compressedSize: directory.getInt32(position + 20),
				size: directory.getInt32(position + 24),
				offset: directory.getInt32(position + 42),
				isDirectory: StringTools.endsWith(name, '/'),
				// Unix mode in the high half of the external attributes: S_IFLNK.
				isLink: ((attributes >>> 16) & 0xf000) == 0xa000
			};

			if (flags & 1 != 0)
				throw 'Encrypted archives are not supported';

			if (!entry.isDirectory && method != 0 && method != 8)
				throw 'Unsupported compression for ${entry.name}';

			if (entry.size < 0 || entry.compressedSize < 0 || entry.offset < 0 || entry.offset + entry.compressedSize > fileSize)
				throw 'Unsupported or damaged entry ${entry.name}';

			entries.push(entry);
			position += 46 + nameLength + extraLength + commentLength;
		}
	}

	private function readBytes(length:Int):Bytes
	{
		var bytes = Bytes.alloc(length);
		input.readFullBytes(bytes, 0, length);
		return bytes;
	}

	/** Raw deflate into a buffer of exactly `size` bytes, so a lying entry can't produce more than it declared. */
	private static function inflate(data:Bytes, size:Int, name:String):Bytes
	{
		var output = Bytes.alloc(size);

		if (size == 0)
			return output;

		#if (cpp || neko || hl || eval || java)
		var uncompress = new haxe.zip.Uncompress(-15);
		var result = try uncompress.execute(data, 0, output, 0) catch (e:Dynamic) null;
		uncompress.close();

		if (result == null || !result.done || result.write != size)
			throw 'Damaged archive: could not decompress $name';
		#else
		var written = 0;

		try
		{
			var reader = new haxe.zip.InflateImpl(new haxe.io.BytesInput(data), false, false);

			while (written < size)
			{
				var read = reader.readBytes(output, written, size - written);

				if (read <= 0)
					break;

				written += read;
			}
		}
		catch (e:Dynamic) {}

		if (written != size)
			throw 'Damaged archive: could not decompress $name';
		#end

		return output;
	}
	#end
}

typedef ArchiveEntry =
{
	/** Path inside the archive, always with `/`. Folders end with `/`. */
	var name:String;

	/** 0 stored, 8 deflated. */
	var method:Int;

	var crc:Int;
	var compressedSize:Int;

	/** Size once decompressed, as the archive declares it. `read()` refuses data that doesn't match. */
	var size:Int;

	var offset:Int;
	var isDirectory:Bool;

	/** A symbolic link. These are never extracted. */
	var isLink:Bool;
}
