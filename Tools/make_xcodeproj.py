#!/usr/bin/env python3
"""
make_xcodeproj.py — writes OpenAdventure.xcodeproj/project.pbxproj.

Regenerate after adding or removing files:
    python3 Tools/make_xcodeproj.py

Upstream engine sources (Engine/upstream/*.c) appear in the project for
reference but are NOT compiled directly; Engine/wrap/*_ios.c include them
after the iOS overrides. Everything else under OpenAdventure/ is built.
"""
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUNDLE_ID = "com.example.OpenAdventure"  # change to your own reverse-DNS id


def oid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


FILE_TYPES = {
    ".swift": "sourcecode.swift", ".c": "sourcecode.c.c", ".h": "sourcecode.c.h",
    ".metal": "sourcecode.metal", ".json": "text.json", ".txt": "text",
    ".xcassets": "folder.assetcatalog", ".py": "text.script.python",
    ".md": "net.daringfireball.markdown", ".yaml": "text.yaml",
}

COMPILE_EXT = {".swift", ".c", ".metal"}
RESOURCE_EXT = {".json", ".txt", ".xcassets"}


def walk(rel_dir, include_build):
    """Return a group tree for rel_dir. include_build: compile/resources?"""
    abs_dir = os.path.join(ROOT, rel_dir)
    children = []
    for name in sorted(os.listdir(abs_dir)):
        if name.startswith(".") or name in ("upstream-tests", "__pycache__"):
            continue
        rel = os.path.join(rel_dir, name)
        abs_path = os.path.join(ROOT, rel)
        ext = os.path.splitext(name)[1]
        if os.path.isdir(abs_path) and ext != ".xcassets":
            children.append(walk(rel, include_build))
        else:
            children.append({"file": rel, "name": name, "ext": ext,
                             "build": include_build(rel, ext)})
    return {"group": rel_dir, "name": os.path.basename(rel_dir), "children": children}


def app_build(rel, ext):
    if rel.endswith("Bridging-Header.h"):
        return None
    if ext in COMPILE_EXT:
        return "source"
    if ext in RESOURCE_EXT:
        return "resource"
    return None


def engine_build(rel, ext):
    if rel.startswith("Engine/wrap/") and ext == ".c":
        return "source"
    if rel == "Engine/shim/advent_bridge.c":
        return "source"
    return None


def no_build(rel, ext):
    return None


def main():
    tree = [
        walk("OpenAdventure", app_build),
        walk("Engine", engine_build),
        walk("Tools", no_build),
    ]
    readme = {"file": "README.md", "name": "README.md", "ext": ".md", "build": None}

    objects = {}
    sources, resources = [], []

    def add_file(node):
        fid = oid("file", node["file"])
        ftype = FILE_TYPES.get(node["ext"], "text")
        objects[fid] = (f'{{isa = PBXFileReference; lastKnownFileType = {ftype}; '
                        f'name = "{node["name"]}"; path = "{node["file"]}"; sourceTree = SOURCE_ROOT; }}')
        if node["build"]:
            bid = oid("build", node["file"])
            objects[bid] = f'{{isa = PBXBuildFile; fileRef = {fid}; }}'
            (sources if node["build"] == "source" else resources).append(bid)
        return fid

    def add_group(node):
        gid = oid("group", node["group"])
        kids = []
        for child in node["children"]:
            kids.append(add_group(child) if "group" in child else add_file(child))
        objects[gid] = (f'{{isa = PBXGroup; children = ({", ".join(kids)}, ); '
                        f'name = "{node["name"]}"; sourceTree = "<group>"; }}')
        return gid

    top = [add_group(g) for g in tree] + [add_file(readme)]

    product = oid("product")
    objects[product] = ('{isa = PBXFileReference; explicitFileType = wrapper.application; '
                        'includeInIndex = 0; path = OpenAdventure.app; sourceTree = BUILT_PRODUCTS_DIR; }')
    products_group = oid("group", "Products")
    objects[products_group] = (f'{{isa = PBXGroup; children = ({product}, ); name = Products; '
                               f'sourceTree = "<group>"; }}')
    main_group = oid("group", "main")
    objects[main_group] = (f'{{isa = PBXGroup; children = ({", ".join(top)}, {products_group}, ); '
                           f'sourceTree = "<group>"; }}')

    src_phase, res_phase, fw_phase = oid("phase", "sources"), oid("phase", "resources"), oid("phase", "frameworks")
    objects[src_phase] = (f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; '
                          f'files = ({", ".join(sources)}, ); runOnlyForDeploymentPostprocessing = 0; }}')
    objects[res_phase] = (f'{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; '
                          f'files = ({", ".join(resources)}, ); runOnlyForDeploymentPostprocessing = 0; }}')
    objects[fw_phase] = ('{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; '
                         'files = ( ); runOnlyForDeploymentPostprocessing = 0; }')

    common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.0",
    }
    target_settings = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "YES",
        "HEADER_SEARCH_PATHS": '("$(SRCROOT)/Engine/shim", "$(SRCROOT)/Engine/upstream", )',
        "INFOPLIST_KEY_CFBundleDisplayName": "Adventure",
        "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO",
        "INFOPLIST_KEY_LSApplicationCategoryType": '"public.app-category.adventure-games"',
        "INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace": "YES",
        "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
        "INFOPLIST_KEY_UIFileSharingEnabled": "YES",
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
        "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks", )',
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_OBJC_BRIDGING_HEADER": '"OpenAdventure/OpenAdventure-Bridging-Header.h"',
        "TARGETED_DEVICE_FAMILY": '"1,2"',
        # The upstream C is written for strict C99; don't let Xcode's extra
        # warnings fail the build.
        "GCC_TREAT_WARNINGS_AS_ERRORS": "NO",
        "CLANG_WARN_STRICT_PROTOTYPES": "NO",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "NO",
    }

    def quoted(v):
        """Bare words are fine in pbxproj; anything else needs quotes."""
        if v.startswith(("(", '"')) or v.replace("_", "").replace(".", "").isalnum():
            return v
        return '"' + v.replace('"', '\\"') + '"'

    def config(name, extra):
        settings = dict(extra)
        body = " ".join(f"{k} = {quoted(v)};" for k, v in sorted(settings.items()))
        return f'{{isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {name}; }}'

    proj_debug, proj_release = oid("cfg", "proj", "Debug"), oid("cfg", "proj", "Release")
    debug_extra = dict(common, **{"DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES",
                                  "GCC_OPTIMIZATION_LEVEL": "0", "ONLY_ACTIVE_ARCH": "YES",
                                  "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
                                  "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
                                  "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
                                  "GCC_PREPROCESSOR_DEFINITIONS": '("DEBUG=1", "$(inherited)", )'})
    release_extra = dict(common, **{"DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
                                    "ENABLE_NS_ASSERTIONS": "NO", "VALIDATE_PRODUCT": "YES",
                                    "SWIFT_COMPILATION_MODE": "wholemodule",
                                    "MTL_ENABLE_DEBUG_INFO": "NO"})
    objects[proj_debug] = config("Debug", debug_extra)
    objects[proj_release] = config("Release", release_extra)
    tgt_debug, tgt_release = oid("cfg", "tgt", "Debug"), oid("cfg", "tgt", "Release")
    objects[tgt_debug] = config("Debug", target_settings)
    objects[tgt_release] = config("Release", target_settings)

    proj_list, tgt_list = oid("cfglist", "proj"), oid("cfglist", "tgt")
    objects[proj_list] = (f'{{isa = XCConfigurationList; buildConfigurations = ({proj_debug}, {proj_release}, ); '
                          f'defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
    objects[tgt_list] = (f'{{isa = XCConfigurationList; buildConfigurations = ({tgt_debug}, {tgt_release}, ); '
                         f'defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')

    target = oid("target")
    objects[target] = (f'{{isa = PBXNativeTarget; buildConfigurationList = {tgt_list}; '
                       f'buildPhases = ({src_phase}, {fw_phase}, {res_phase}, ); buildRules = ( ); '
                       f'dependencies = ( ); name = OpenAdventure; productName = OpenAdventure; '
                       f'productReference = {product}; productType = "com.apple.product-type.application"; }}')

    project = oid("project")
    objects[project] = (f'{{isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = 1; '
                        f'LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; '
                        f'TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 16.0; }}; }}; }}; '
                        f'buildConfigurationList = {proj_list}; compatibilityVersion = "Xcode 14.0"; '
                        f'developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base, ); '
                        f'mainGroup = {main_group}; productRefGroup = {products_group}; projectDirPath = ""; '
                        f'projectRoot = ""; targets = ({target}, ); }}')

    lines = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};",
             "\tobjectVersion = 56;", "\tobjects = {"]
    for key in sorted(objects):
        lines.append(f"\t\t{key} = {objects[key]};")
    lines += ["\t};", f"\trootObject = {project};", "}", ""]

    out_dir = os.path.join(ROOT, "OpenAdventure.xcodeproj")
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "project.pbxproj"), "w") as fh:
        fh.write("\n".join(lines))
    print(f"{len(sources)} sources, {len(resources)} resources")


if __name__ == "__main__":
    main()
