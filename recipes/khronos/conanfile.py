from conans import ConanFile

class KhronosConan(ConanFile):
    """Stand-in for TAK's private khronos/1.0 package.

    The engine consumes it only as ${khronos_INCLUDE_DIRS}, for <GLES2/gl2.h>,
    <GLES3/gl3.h> and friends. On Android the NDK sysroot already provides
    those headers, so this package is deliberately empty: it exists so that
    conan resolution and find_package(khronos) succeed.
    """
    name = "khronos"
    version = "1.0"
    description = "Khronos GL/EGL headers (empty on Android: the NDK supplies them)"

    def package_id(self):
        self.info.header_only()
