package = "zet"
version = "dev-1"
source = {
   url = "*** please add URL for source tarball, zip or repository here ***"
}
description = {
   homepage = "*** please enter a project homepage ***",
   license = "*** please specify a license ***"
}
dependencies = {
   "debugger = scm-1",
   "ldoc = 1.5.0-1",
   "ltui = 2.7",
   "inspect >= 3.1",
   "lua ~> 5.4",
   queries = {
      {
         constraints = {
            {
               op = "~>",
               version = {
                  5, 4, string = "5.4"
               }
            }
         },
         name = "lua"
      }
   }
}
build_dependencies = {
   "debugger = scm-1",
   "ldoc = 1.5.0-1",
   "ltui = 2.7",
   "inspect >= 3.1",
   queries = {}
}
build = {
   type = "builtin",
   modules = {
      main = "src/zet.lua",
      setup = "src/setup.lua"
   }
}
test_dependencies = {
   "debugger = scm-1",
   "ldoc = 1.5.0-1",
   "ltui = 2.7",
   "inspect >= 3.1",
   queries = {}
}
