@tool
extends EditorPlugin

# Editor plugin that packages the MarkerAR Android plugin (v2 Android plugin):
# the AAR under bin/{debug,release} is picked up by the Android exporter and
# OpenCV is declared as a remote Maven dependency of the app build.

var export_plugin : AndroidExportPlugin


func _enter_tree():
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree():
	remove_export_plugin(export_plugin)
	export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	var _plugin_name = "MarkerARPlugin"
	var _opencv_version = "4.12.0"

	func _supports_platform(platform):
		if platform is EditorExportPlatformAndroid:
			return true
		return false

	func _get_android_libraries(platform, debug):
		if debug:
			return PackedStringArray([_plugin_name + "/bin/debug/" + _plugin_name + "-debug.aar"])
		else:
			return PackedStringArray([_plugin_name + "/bin/release/" + _plugin_name + "-release.aar"])

	func _get_android_dependencies(platform, debug):
		return PackedStringArray(["org.opencv:opencv:" + _opencv_version])

	func _get_android_dependencies_maven_repos(platform, debug):
		return PackedStringArray(["https://repo1.maven.org/maven2/"])

	func _get_name():
		return _plugin_name
