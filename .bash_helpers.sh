#
# Copyright (c) 2008-2016 the Urho3D project.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

# Detect markers in the build tree
if [[ -f "$BUILD"/.fix-scm ]]; then FIX_SCM=1; fi

# Define helpers
post_cmake() {
    if [[ $ECLIPSE ]]; then
        # Check if xmlstarlet software package is available for fixing the generated Eclipse project setting
        if xmlstarlet --version >/dev/null 2>&1; then HAS_XMLSTARLET=1; fi
        if [[ $HAS_XMLSTARLET ]]; then
            # Common fixes for all builds
            #
            # Remove build configuration from project name
            # Replace deprecated GNU gmake Error Parser with newer version (6.0 -> 7.0) and add GCC Error Parser
            #
            xmlstarlet ed -P -L \
                -u "/projectDescription/name/text()" -x "concat(substring-before(., '-Release'), substring-before(., '-Debug'), substring-before(., '-RelWithDebInfo'))" \
                -u "/projectDescription/buildSpec/buildCommand/arguments/dictionary/value[../key/text() = 'org.eclipse.cdt.core.errorOutputParser']" -x "concat('org.eclipse.cdt.core.GmakeErrorParser;org.eclipse.cdt.core.GCCErrorParser;', substring-after(., 'org.eclipse.cdt.core.MakeErrorParser'))" \
                "$BUILD"/.project

            # Build-specific fixes
            if [[ $ANDROID ]]; then
                # For Android build, add the Android and Java nature to the project setting as it would be done by Eclipse during project import
                # This fix avoids the step to reimport the project everytime the Eclipse project setting is regenerated by cmake_generic.sh invocation
                echo -- post_cmake: Add Android and Java nature to Eclipse project setting files in $BUILD

                #
                # Add natures (Android nature must be inserted as first nature)
                #
                xmlstarlet ed -P -L \
                    -i "/projectDescription/natures/nature[1]" -t elem -n nature -v "com.android.ide.eclipse.adt.AndroidNature" \
                    -s "/projectDescription/natures" -t elem -n nature -v "org.eclipse.jdt.core.javanature" \
                    "$BUILD"/.project
                #
                # Add build commands
                #
                for c in com.android.ide.eclipse.adt.ResourceManagerBuilder com.android.ide.eclipse.adt.PreCompilerBuilder org.eclipse.jdt.core.javabuilder com.android.ide.eclipse.adt.ApkBuilder; do
                    xmlstarlet ed -P -L \
                        -s "/projectDescription/buildSpec" -t elem -n buildCommandNew -v "" \
                        -s "/projectDescription/buildSpec/buildCommandNew" -t elem -n name -v $c \
                        -s "/projectDescription/buildSpec/buildCommandNew" -t elem -n arguments -v "" \
                        -r "/projectDescription/buildSpec/buildCommandNew" -v "buildCommand" \
                        "$BUILD"/.project
                done
            fi

            if [[ $FIX_SCM ]]; then
                # Copy the Eclipse project setting files to Source tree in order to fix it so that Eclipse's SCM feature works again
                echo -- post_cmake: Move Eclipse project setting files to $SOURCE and fix them to reenable Eclipse SCM feature
                # Leave the original copy in the build tree
                for f in .project .cproject; do cp "$BUILD"/$f "$SOURCE"; done
                # Set a marker in the build tree that Eclipse project has been fixed
                touch "$BUILD"/.fix-scm

                #
                # Replace [Source directory] linked resource to [Build] instead
                # Modify build argument to first change directory to Build folder
                # Remove [Subprojects]/Urho3D linked resource
                #
                xmlstarlet ed -P -L \
                    -u "/projectDescription/linkedResources/link/name/text()[. = '[Source directory]']" -v "[Build]" \
                    -u "/projectDescription/linkedResources/link/location[../name/text() = '[Build]']" -v "`cd $BUILD; pwd`" \
                    -u "/projectDescription/buildSpec/buildCommand/arguments/dictionary/value[../key/text() = 'org.eclipse.cdt.make.core.build.arguments']" -x "concat('-C $BUILD ', .)" \
                    -d "/projectDescription/linkedResources/link[./name = '[Subprojects]/Urho3D']" \
                    "$SOURCE"/.project
                #
                # Fix source path entry to Source folder and modify its filter condition
                # Fix output path entry to [Build] linked resource and modify its filter condition
                #
                xmlstarlet ed -P -L \
                    -u "/cproject/storageModule/cconfiguration/storageModule/pathentry[@kind = 'src']/@path" -v "" \
                    -s "/cproject/storageModule/cconfiguration/storageModule/pathentry[@kind = 'src']" -t attr -n "excluding" -v "[Build]/|[Subprojects]/|[Targets]/|Docs/AngelScriptAPI.h" \
                    -u "/cproject/storageModule/cconfiguration/storageModule/pathentry[@kind = 'out']/@path" -v "[Build]" \
                    -u "/cproject/storageModule/cconfiguration/storageModule/pathentry[@kind = 'out']/@excluding" -x "substring-after(., '[Source directory]/|')" \
                    "$SOURCE"/.cproject
            fi
        fi
    elif [ -e "$BUILD"/*.xcodeproj/project.pbxproj ] && perl -v >/dev/null 2>&1; then
        echo -- post_cmake: Fix generated Xcode project
        # Temporary workaround to fix file references being added into multiple groups warnings (CMake bug http://www.cmake.org/Bug/view.php?id=15272, stil exists in 3.1)
        perl -i -pe 'BEGIN {$/=undef} s/(Begin PBXGroup section.*?\/\* Sources \*\/,).*?,/\1/s' "$BUILD"/*.xcodeproj/project.pbxproj
        # Speed up build for Debug build configuration by building only active arch (currently this is not doable via CMake generator-expression as it only works for individual target instead of global)
        perl -i -pe 'BEGIN {$/=undef} s/(Debug \*\/ = {[^}]+?)SDKROOT/\1ONLY_ACTIVE_ARCH = YES; SDKROOT/s' "$BUILD"/*.xcodeproj/project.pbxproj
        # Speed up build for Debug build configuration by skipping dSYM file generation
        if [[ $IOS ]]; then
            perl -i -pe 'BEGIN {$/=undef} s/(Debug \*\/ = {[^}]+?)SDKROOT/\1DEBUG_INFORMATION_FORMAT = dwarf; SDKROOT/s' "$BUILD"/*.xcodeproj/project.pbxproj
        fi
    fi
}

# vi: set ts=4 sw=4 expandtab:
