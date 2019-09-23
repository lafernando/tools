import laf/zip;
import ballerina/file;
import ballerina/io;
import ballerina/system;

public function main(string... args) returns error? {
    string sourcedir = <@untainted> args[0];
    string aotcFile = <@untainted> args[1];
    string jarFile = check generateJar(sourcedir);
    check generateAOTCLib(jarFile, aotcFile);
}

function generateAOTCLib(string jarFile, string aotcFile) returns error? {
    io:println("Executing jaotc...");
    string[] params = [];
    params.push("--ignore-errors");
    params.push(jarFile);
    params.push("--output");
    params.push(aotcFile);
    params.push("--info");
    params.push("-J-Xmx12g");
    system:Process process = check system:exec("jaotc", {}, (), ...params);
    io:ReadableCharacterChannel cch = new(process.stdout(), "UTF-8");
    io:WritableCharacterChannel cch2 = new(check io:openWritableFile("jaotc-log.txt"), "UTF-8");
    while (true) {
        var result = cch.read(300);
        if (result is io:EofError) {
            break;
        } else {
            check writeFully(check result, cch2);
        }
    }
    check cch2.close();
    check cch.close();
    _ = check process.waitForExit();
    io:println("Generated: " + aotcFile);
}

function generateJar(string sourcedir) returns string|error {
    string baseTmp = file:tempDir();
    var ign = file:remove(baseTmp + "/out/", true);
    ign = file:remove(baseTmp + "/outall/", true);
    string outdir = check file:createDir(baseTmp + "/out/");
    string outalldir = check file:createDir(baseTmp + "/outall/");
    string targetfile = baseTmp + "/bout.jar";
    
    file:FileInfo[] files = check file:readDir(sourcedir, 1);
    foreach var fx in files {
        if (!fx.getName().endsWith(".jar")) { continue; }
        io:println("Processing jar: ", fx.getName());
        string dirpath = check file:createDir(outdir + "/" + fx.getName(), true);
        check zip:unzip(sourcedir + fx.getName(), dirpath);
        check mergeDir(dirpath, outalldir, fx.getName());
    }

    io:println("Generating final jar...");
    check zip:zip(outalldir, targetfile);
    io:println("Generated: ", targetfile);
    return targetfile;
}

function mergeDir(string sourcedir, string targetdir, string x) returns error? {
    // max depth used due to issue: https://github.com/ballerina-platform/ballerina-lang/issues/19149
    file:FileInfo[] files = check file:readDir(sourcedir, 1);
    foreach var fx in files {
        // bug: https://github.com/ballerina-platform/ballerina-lang/issues/19148
        if (fx.getName() == x) { continue; }
        if (fx.isDir()) {
            string td = targetdir + "/" + fx.getName();
            var ign = file:createDir(td);
            check mergeDir(sourcedir + "/" + fx.getName(), td, fx.getName());
        } else {
            check copyFile(sourcedir + "/" + fx.getName(), targetdir + "/" + fx.getName());
        }
    }
}

function copyFile(string src, string target) returns error? {
    // ignore signature files
    if (src.indexOf("/META-INF/") is int && (src.endsWith(".SF") || src.endsWith(".DSA"))) {
        return;
    }
    if (src.indexOf("/META-INF/services") is int && file:exists(target)) {
        check mergeFiles(src, target);
        return;
    } 
    check file:copy(src, target);
}

function mergeFiles(string src, string target) returns error? {
    io:WritableByteChannel bch = check io:openWritableFile(target, true);
    io:WritableCharacterChannel cch = new(bch, "UTF-8");
    check writeFully("\n", cch);
    io:ReadableByteChannel bch2 = check io:openReadableFile(src);
    io:ReadableCharacterChannel cch2 = new(bch2, "UTF-8");
    while (true) {
        var result = cch2.read(100);
        if (result is io:EofError) {
            break;
        } else if (result is error) {
            return <@untainted> result;
        } else {
            check writeFully(result, cch);
        }
    }
    check cch.close();
    check cch2.close();
    check bch.close();
    check bch2.close();
}

function writeFully(string content, io:WritableCharacterChannel cch) returns error? {
    int i = 0;
    while (i < content.length()) {
        i += check cch.write(content, i);
    }
}
