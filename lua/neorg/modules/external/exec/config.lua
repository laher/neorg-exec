return {
    default_metadata = {
      enabled = true,
      session = nil,
      out = "inplace",
      env = {
        NEORG = 1,
      },
    },
    lang_cmds = {
        --> Interpreted
        python = {
            cmd = "python3 ${0}",
            type = "interpreted",
            repl = "python3",
        },
        lua = {
            cmd = "lua ${0}",
            type = "interpreted",
            repl = "lua -i",
        },
        javascript = {
            cmd = "node ${0}",
            type = "interpreted",
            repl = "node",
        },
        bash = {
            cmd = "bash ${0}",
            type = "interpreted",
            repl = "bash",
        },
        zsh = {
            cmd = "zsh ${0}",
            type = "interpreted",
            repl = "zsh",
        },
        php = {
            cmd = "php ${0}",
            type = "interpreted",
        },
        ruby = {
            cmd = "ruby ${0}",
            type = "interpreted",
            repl = "ruby",
        },

        --> Compiled
        cpp = {
            cmd = "g++ ${0} && ./a.out && rm ./a.out",
            type = "compiled",
            main_wrap = [[
            #include <iostream>
            int main() {
                ${1}
            }
            ]],
        },
        go = {
            cmd = "goimports -w ${0} && NO_COLOR=1 go run ${0}",
            type = "compiled",
            main_wrap = [[
            package main

            func main() {
                ${1}
            }
            ]],
        },
        c = {
            cmd = "gcc ${0} && ./a.out && rm ./a.out",
            type = "compiled",
            main_wrap = [[
            #include <stdio.h>
            #include <stdlib.h>

            int main() {
                ${1}
            }
            ]],
        },
        rust = {
            cmd = "rustc ${0} -o ./a.out && ./a.out && rm ./a.out",
            type = "compiled",
            main_wrap = [[
            fn main() {
                ${1}
            }
            ]],
        },
    },
}
