import os
from conans import ConanFile

class DracoConan(ConanFile):
    """Stand-in for TAK's private draco/1.5.7 package.

    cesium-native's vcpkg build has already produced libdraco.a and the draco
    headers. DRACO_PREFIX points at that vcpkg install tree; this recipe just
    re-homes it as a conan package.

    The headers matter: tinygltf includes <draco/compression/decode.h>, so
    include/draco/ must keep its directory level in the package. An earlier
    version of this recipe flattened it and the engine failed to compile.
    """
    name = "draco"
    version = "1.5.7"
    settings = "os", "compiler", "build_type", "arch"

    def package(self):
        p = os.environ["DRACO_PREFIX"]
        self.copy("*", dst="include/draco", src=os.path.join(p, "include", "draco"), keep_path=True)
        self.copy("libdraco.a", dst="lib", src=os.path.join(p, "lib"))

    def package_info(self):
        self.cpp_info.libs = ["draco"]
