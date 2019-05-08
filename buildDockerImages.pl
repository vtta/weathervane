#!/usr/bin/perl
# Copyright (c) 2017 VMware, Inc. All Rights Reserved.
# 
# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
# Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
# Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
# INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# Created by: Hal Rosenberg
#
# This builds and pushes the Docker images for Weathervane
#
package BuildDocker;
use strict;
use Getopt::Long;
use Term::ReadKey;

sub usage {
	print "Usage: ./buildDockerImages.pl [options] [imageNames]\n";
	print "This script builds the Weathervane docker images and pushes them to either\n";
	print "a Docker Hub account or a private registry.\n";
    print " Options:\n";
    print "     --help :         Print this help and exit.\n";
    print "     --username:      The username for the Docker Hub account.\n";
    print "                      This must be provided if --private is not used.\n";
    print "     --password:      (optional) The password for the Docker Hub account.\n";
    print "                      If not provided, will be prompted.\n";
    print "     --private :      Use a private Docker registry \n";
    print "     --host :         This is the hostname or IP address for the private registry.\n";
    print "                      This must be provided if --private is used.\n";
    print "     --port :         This is the port number for the private registry.\n";
    print "                      This must be provided if --private is used.\n";
    print "If the list of image names is empty, then all images are built and pushed.\n";
}

my $help = '';
my $host= "";
my $port = 0;
my $username = "";
my $password = "";
my $private = '';

my $optionsSuccess = GetOptions('help' => \$help,
			'host=s' => \$host,
			'port=i' => \$port,
			'username=s' => \$username,
			'password=s' => \$password,
			'private!' => \$private
			);
if (!$optionsSuccess) {
  die "Error for command line options.\n";
}

my @imageNames = qw(centos7 auctiondatamanager auctionworkloaddriver auctionappserverwarmer cassandra nginx postgresql rabbitmq zookeeper tomcat auctionbidservice);
if ($#ARGV >= 0) {
	@imageNames = @ARGV;
}

if ($help) {
	usage();
	exit;
}

sub runAndLog {
	my ( $fileout, $cmd ) = @_;
	print $fileout "COMMAND> $cmd\n";
	open( CMD, "$cmd 2>&1 |" ) || die "Couldn't run command $cmd: $!\n";
	while ( my $line = <CMD> ) {
		print $fileout $line;
	}
	close CMD;
}

sub rewriteDockerfile {
	my ( $dirName, $namespace, $version) = @_;
	`mv $dirName/Dockerfile $dirName/Dockerfile.orig`;
	open(my $filein, "$dirName/Dockerfile.orig") or die "Can't open file $dirName/Dockerfile.orig for reading: $!\n";
	open(my $fileout, ">$dirName/Dockerfile") or die "Can't open file $dirName/Dockerfile for writing: $!\n";
	while (my $inline = <$filein>) {
		if ($inline =~ /^FROM/) {
			print $fileout "FROM $namespace/weathervane-centos7:$version\n";
		} else {
			print $fileout $inline;
		}
	}
	close $filein;
	close $fileout
}

sub cleanupDockerfile {
	my ( $dirName) = @_;
	`mv $dirName/Dockerfile.orig $dirName/Dockerfile`;
}

sub buildImage {
	my ($imageName, $buildArgsListRef, $fileout, $namespace, $version, $logFile) = @_;
	if ($imageName ne "centos7") {		
		rewriteDockerfile("./dockerImages/$imageName", $namespace, $version);
	}

	my $buildArgs = "";
	foreach my $buildArg (@$buildArgsListRef) {
		$buildArgs .= " --build-arg $buildArg";
	}

	runAndLog($fileout, "docker build $buildArgs -t $namespace/weathervane-$imageName:$version ./dockerImages/$imageName");
	my $exitValue;
	$exitValue=$? >> 8;
	if ($exitValue) {
		print "Error: docker build failed with exitValue $exitValue, check $logFile.\n";
		exit;
	}

	runAndLog($fileout, "docker push $namespace/weathervane-$imageName:$version");
	$exitValue=$? >> 8;
	if ($exitValue) {
		print "Error: docker push failed with exitValue $exitValue, check $logFile.\n";
		exit;
	}

	if ($imageName ne "centos7") {		
		cleanupDockerfile("./dockerImages/$imageName");
	}
	
}

my $namespace;
if ($private) {
	if (($host eq "") || ($port==0)) {
		print "When using a private repository, you must specify both the host and port parameters.\n";
		usage();
		exit;
	}
	$namespace = "$host:$port";
} else {
	if ($username eq "") {
			print "When using Docker Hub, you must specify the username parameter.\n";
			usage();
			exit;
	}
	$namespace = $username;
}

if (!(-e "./buildDockerImages.pl")) {
	print "You must run in the weathervane directory with buildDockerImages.pl\n";
	exit;
}

my $cmdout;
my $fileout;
my $logFile = "buildDockerImages.log";
open( $fileout, ">$logFile" ) or die "Can't open file $logFile for writing: $!\n";

# Build the executables
print "Building the executables.\n";
print $fileout "Building the executables.\n";
runAndLog($fileout, "./gradlew release");
my $exitValue=$? >> 8;
if ($exitValue) {
	print "Error: Building failed with exitValue $exitValue, check $logFile.\n";
	exit;
}

# Get the latest executables into the appropriate directories for the Docker images
print "Setting up the Docker images.\n";
print $fileout "Setting up the Docker images.\n";
#nginx
runAndLog($fileout, "rm -rf ./dockerImages/nginx/html");
runAndLog($fileout, "mkdir ./dockerImages/nginx/html");
runAndLog($fileout, "cp ./dist/auctionWeb.tgz ./dockerImages/nginx/html/");
runAndLog($fileout, "cd ./dockerImages/nginx/html; tar zxf auctionWeb.tgz; rm -f auctionWeb.tgz");

# appServerWarmer
runAndLog($fileout, "rm -f ./dockerImages/auctionappserverwarmer/auctionAppServerWarmer.jar");
runAndLog($fileout, "cp ./dist/auctionAppServerWarmer.jar ./dockerImages/auctionappserverwarmer/auctionAppServerWarmer.jar");
# tomcat
runAndLog($fileout, "rm -rf ./dockerImages/tomcat/apache-tomcat-auction1/webapps");
runAndLog($fileout, "mkdir ./dockerImages/tomcat/apache-tomcat-auction1/webapps");
runAndLog($fileout, "mkdir ./dockerImages/tomcat/apache-tomcat-auction1/webapps/auction");
runAndLog($fileout, "mkdir ./dockerImages/tomcat/apache-tomcat-auction1/webapps/auctionWeb");
runAndLog($fileout, "cp ./dist/auction.war ./dockerImages/tomcat/apache-tomcat-auction1/webapps/");
runAndLog($fileout, "cp ./dist/auctionWeb.war ./dockerImages/tomcat/apache-tomcat-auction1/webapps/");
runAndLog($fileout, "cp ./dist/auction.war ./dockerImages/tomcat/apache-tomcat-auction1/webapps/auction/");
runAndLog($fileout, "cd ./dockerImages/tomcat/apache-tomcat-auction1/webapps/auction; jar xf auction.war; rm -f auction.war");
runAndLog($fileout, "cp ./dist/auctionWeb.war ./dockerImages/tomcat/apache-tomcat-auction1/webapps/auctionWeb/");
runAndLog($fileout, "cd ./dockerImages/tomcat/apache-tomcat-auction1/webapps/auctionWeb; jar xf auctionWeb.war; rm -f auctionWeb.war");
# auctionBidService
runAndLog($fileout, "rm -rf ./dockerImages/auctionbidservice/apache-tomcat-bid/webapps");
runAndLog($fileout, "mkdir ./dockerImages/auctionbidservice/apache-tomcat-bid/webapps");
runAndLog($fileout, "mkdir ./dockerImages/auctionbidservice/apache-tomcat-bid/webapps/auction");
runAndLog($fileout, "cp ./dist/auctionBidService.war ./dockerImages/auctionbidservice/apache-tomcat-bid/webapps/auction.war");
runAndLog($fileout, "cp ./dist/auctionBidService.war ./dockerImages/auctionbidservice/apache-tomcat-bid/webapps/auction/auction.war");
runAndLog($fileout, "cd ./dockerImages/auctionbidservice/apache-tomcat-bid/webapps/auction; jar xf auction.war; rm -f auction.war");

# workload driver
runAndLog($fileout, "rm -f ./dockerImages/auctionworkloaddriver/workloadDriver.jar");
runAndLog($fileout, "rm -rf ./dockerImages/auctionworkloaddriver/workloadDriverLibs");
runAndLog($fileout, "cp ./dist/workloadDriver.jar ./dockerImages/auctionworkloaddriver/workloadDriver.jar");
runAndLog($fileout, "cp -r ./dist/workloadDriverLibs ./dockerImages/auctionworkloaddriver/workloadDriverLibs");

# data manager
runAndLog($fileout, "rm -f ./dockerImages/auctiondatamanager/dbLoader.jar");
runAndLog($fileout, "rm -rf ./dockerImages/auctiondatamanager/dbLoaderLibs");
runAndLog($fileout, "cp ./dist/dbLoader.jar ./dockerImages/auctiondatamanager/dbLoader.jar");
runAndLog($fileout, "cp -r ./dist/dbLoaderLibs ./dockerImages/auctiondatamanager/dbLoaderLibs");

# run harness
runAndLog($fileout, "rm -rf ./dockerImages/runharness/runHarness");
runAndLog($fileout, "rm -rf ./dockerImages/runharness/dist");
runAndLog($fileout, "rm -rf ./dockerImages/runharness/configFiles");
runAndLog($fileout, "rm -rf ./dockerImages/runharness/workloadConfiguration");
runAndLog($fileout, "rm -f ./dockerImages/runharness/weathervane.pl");
runAndLog($fileout, "rm -f ./dockerImages/runharness/version.txt");
runAndLog($fileout, "cp ./weathervane.pl ./dockerImages/runharness/weathervane.pl");
runAndLog($fileout, "cp ./version.txt ./dockerImages/runharness/version.txt");
runAndLog($fileout, "cp -r ./runHarness ./dockerImages/runharness/runHarness");
runAndLog($fileout, "cp -r ./dist ./dockerImages/runharness/dist");
runAndLog($fileout, "cp -r ./configFiles ./dockerImages/runharness/configFiles");
runAndLog($fileout, "cp -r ./workloadConfiguration ./dockerImages/runharness/workloadConfiguration");


my $version = `cat version.txt`;
chomp($version);

# Turn on auto flushing of output
BEGIN { $| = 1 }

if (!$private) {
	if (!(length $password > 0)) {
		Term::ReadKey::ReadMode('noecho');
		print "Enter Docker Hub password for $username:";
		$password = Term::ReadKey::ReadLine(0);
		Term::ReadKey::ReadMode('restore');
		print "\n";
		$password =~ s/\R\z//; #get rid of new line
	}

	if (!(length $password > 0)) {
		die "Error, no password input.\n";
	}

	print "Logging into Docker Hub.\n";
	print $fileout "Logging into Docker Hub.\n";
	my $cmd = "docker login -u $username -p $password";
	my $response = `$cmd 2>&1`;
	if ($response =~ /unauthorized/) {
		print "Could not log into Docker Hub with the supplied username and password.\n";
		exit;
	}
	print $fileout "result: $response\n";
}

foreach my $imageName (@imageNames) {
	print "Building and pushing weathervane-$imageName image.\n";
	print $fileout "Building and pushing weathervane-$imageName image.\n";
	my @buildArgs;
	
	if ($imageName eq "zookeeper") {
		# Figure out the latest version of Zookeeper
		my $zookeeperGet = `curl -s http://www.us.apache.org/dist/zookeeper/stable/`;
		$zookeeperGet =~ />zookeeper-(\d+\.\d+\.\d+)\.tar\.gz</;
		my $zookeeperVers = $1;
		push @buildArgs, "ZOOKEEPER_VERSION=$zookeeperVers";
	} elsif (($imageName eq "tomcat") || ($imageName eq "auctionbidservice")) {
		my $tomcat8get = `curl -s http://www.us.apache.org/dist/tomcat/tomcat-8/`;
		$tomcat8get =~ />v8\.5\.(\d+)\//;
		my $tomcat8vers = $1;
		push @buildArgs, "TOMCAT_VERSION=$tomcat8vers";		
	}
	
	buildImage($imageName, \@buildArgs, $fileout, $namespace, $version, $logFile);
}

# Clean up
print $fileout "Cleaning up.\n";
runAndLog($fileout, "rm -rf ./dockerImages/nginx/html");
runAndLog($fileout, "rm -f ./dockerImages/auctionappserverwarmer/auctionAppServerWarmer.jar");
runAndLog($fileout, "rm -rf ./dockerImages/tomcat/apache-tomcat-auction1/webapps");
runAndLog($fileout, "rm -rf ./dockerImages/auctionBidService/apache-tomcat-bid/webapps");
runAndLog($fileout, "rm -f ./dockerImages/auctionworkloaddriver/workloadDriver.jar");
runAndLog($fileout, "rm -rf ./dockerImages/auctionworkloaddriver/workloadDriverLibs");
runAndLog($fileout, "rm -f ./dockerImages/auctiondatamanager/dbLoader.jar");
runAndLog($fileout, "rm -rf ./dockerImages/auctiondatamanager/dbLoaderLibs");
runAndLog($fileout, "rm -rf ./dockerImages/runharness/runHarness");
runAndLog($fileout, "rm -rf ./dockerImages/runharness/dist");
runAndLog($fileout, "rm -rf ./dockerImages/runharness/configFiles");
runAndLog($fileout, "rm -rf ./dockerImages/runharness/workloadConfiguration");
runAndLog($fileout, "rm -f ./dockerImages/runharness/weathervane.pl");
runAndLog($fileout, "rm -f ./dockerImages/runharness/version.txt");

print "Done.\n";
print $fileout "Done.\n";

1;
