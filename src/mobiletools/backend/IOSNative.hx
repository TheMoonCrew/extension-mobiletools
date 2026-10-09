package mobiletools.backend;

#if (cpp && ios)
import cpp.ConstCharStar;

/**
 * Direct bindings to the Objective-C++ implementation in `project/ios/MobileToolsIOS.mm`.
 *
 * The native file is compiled into the app by hxcpp through `mobiletools_ios.xml`.
 * Use `IOSBackend` instead of calling this directly.
 */
@:include('MobileToolsIOS.h')
@:buildXml("<include name='${haxelib:extension-mobiletools}/project/ios/mobiletools_ios.xml' />")
extern class IOSNative
{
	@:native('mobiletools::ios::showToast')
	static function showToast(message:ConstCharStar, duration:Int):Void;

	@:native('mobiletools::ios::vibrate')
	static function vibrate():Void;

	@:native('mobiletools::ios::setKeepScreenOn')
	static function setKeepScreenOn(enabled:Bool):Void;

	@:native('mobiletools::ios::getDeviceInfo')
	static function getDeviceInfo():ConstCharStar;

	@:native('mobiletools::ios::checkPermission')
	static function checkPermission(permission:ConstCharStar):Int;

	@:native('mobiletools::ios::requestPermission')
	static function requestPermission(permission:ConstCharStar):Void;

	@:native('mobiletools::ios::isPermissionRequestPending')
	static function isPermissionRequestPending(permission:ConstCharStar):Bool;

	@:native('mobiletools::ios::openSettings')
	static function openSettings():Void;
}
#end
