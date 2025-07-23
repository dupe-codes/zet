package = "zet"
version = "dev-1"
source = {
    url = "*** please add URL for source tarball, zip or repository here ***",
}
description = {
    homepage = "*** please enter a project homepage ***",
    license = "*** please specify a license ***",
}
dependencies = {
    "debugger = scm-1",
    "ldoc = 1.5.0-1",
    "inspect >= 3.1",
    "lua ~> 5.1",
    "lua-yaml = 1.2-2"
}
build = {
    type = "builtin",
    modules = {
        main = "src/zet.lua",
        setup = "src/setup.lua",
    },
}
