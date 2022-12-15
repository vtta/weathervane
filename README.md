Please **DO NOT** use this. It is pure junk! I utterly don't understand why gradle needs 20 mins on a 144core machine w/ 1G networking to build this shit! The only reason I am trying this is because the prebuilt binary (VMmark v3.1.1) provided by vmware is corrupted (why??????). And then my precious evening is gone for nothing! 🖕 VMware.

## Building

```bash
aria2c -c -x 16 -k 1M -j 1 https://cfdownload.adobe.com/pub/adobe/coldfusion/java/java8/java8u351/jdk/jdk-8u351-linux-x64.tar.gz
tar axvf jdk-8u351-linux-x64.tar.gz
JAVA_HOME=$(pwd)/jdk1.8.0_351 TERM=xterm-color ./gradlew --parallel=true clean release
./buildDockerImages.pl
# currently failing: postgresql9.3 does not exist anymore
```

