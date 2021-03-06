load("//node:internal/node_utils.bzl", "execute", "init_module", "mangle_package_name")

def _yarn_repository_impl(ctx):
    node = ctx.path(ctx.attr._node)
    nodedir = node.dirname.dirname
    yarn = ctx.path(ctx.attr._yarn)

    execute(ctx, ["cp", ctx.path(ctx.attr.package), ctx.path(".")])
    execute(ctx, ["cp", ctx.path(ctx.attr.lockfile), ctx.path(".")])

    cmd = [
        node,
        yarn,
        "install",
        "--frozen-lockfile",
        "--non-interactive",
    ]

    if not ctx.attr.use_global_yarn_cache:
        cmd += ["--cache-folder", ctx.path("._yarncache")]
    else:
        cmd += ["--mutex", "network"]

    if ctx.attr.registry:
        cmd += ["--registry", ctx.attr.registry]

    execute(ctx, cmd, path = "%s/bin" % nodedir)

    modules_path = ctx.path("node_modules")
    execute(ctx, ["find", modules_path, "-iname", "build", "-type", "f", "-exec", "mv", "{}", "{}.js", ";"])

    # Rename and move scoped modules with invalid bazel labels
    for module in modules_path.readdir():
        if module.basename.startswith("@"):
            for scoped_module in module.readdir():
                execute(ctx, ["mv", scoped_module, "%s/%s" % (modules_path, mangle_package_name(module.basename, scoped_module.basename))])
            execute(ctx, ["rm", "-rf", module])

    if ctx.attr.seal:
        ctx.file(
            "BUILD",
            """package(default_visibility = ["//visibility:public"])
load("@com_happyco_rules_node//node:rules.bzl", "sealed_module_group")

sealed_module_group(name = "node_modules", srcs = glob(include = ["node_modules/*"], exclude = ["node_modules/.*"], exclude_directories = 0))
""",
            executable = False,
        )
    else:
        modules = []
        for module in modules_path.readdir():
            if module.basename.startswith("."):
                continue
            modules.append("//%s:node_module" % (module.basename))
            init_module(ctx, module)

        execute(ctx, ["rm", "-rf", modules_path])
        ctx.file(
            "BUILD",
            """package(default_visibility = ["//visibility:public"])
load("@com_happyco_rules_node//node:rules.bzl", "module_group")

module_group(name = "node_modules", srcs = %s)
""" % (str(modules)),
            executable = False,
        )

    if ctx.attr.postinstall:
        execute(ctx, ctx.attr.postinstall)

yarn_repository = repository_rule(
    attrs = {
        "registry": attr.string(),
        "package": attr.label(
            mandatory = True,
            single_file = True,
            allow_files = ["package.json"],
        ),
        "lockfile": attr.label(
            mandatory = True,
            single_file = True,
            allow_files = ["yarn.lock"],
        ),
        "indeps": attr.string_list_dict(),
        "postinstall": attr.string_list(),
        "seal": attr.bool(),
        "use_global_yarn_cache": attr.bool(default = True),
        "_node": attr.label(
            default = Label("@com_happyco_rules_node_toolchain//:bin/node"),
            single_file = True,
            allow_files = True,
            executable = True,
            cfg = "host",
        ),
        "_yarn": attr.label(
            default = Label("@com_happyco_rules_node_toolchain//:bin/yarn"),
            single_file = True,
            allow_files = True,
            executable = True,
            cfg = "host",
        ),
        "_deps": attr.label(
            default = Label("//node/tools:deps.js"),
            single_file = True,
            allow_files = True,
            executable = True,
            cfg = "host",
        ),
    },
    implementation = _yarn_repository_impl,
)
