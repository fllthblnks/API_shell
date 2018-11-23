# API_shell for ArubaOS 8.x
Description
-----------
This tool was built to assist in troubleshooting larger ArubaOS 8.x cluster by allowing the user to run the commands from a single interface instead of having to go on each controller to run the commands individually.

It leverages the ArubaOS 8.x REST API.

Usage
-----
Start the script using perl API_shell -h to get the help information

Usage: API_shell.pl [options] [MM ipaddr]

Options:
     -s <file>        file of standalone name,ipaddr to connect to
     -u <username>    Specify ssh/webui username, default is admin
     -p <password>    Specify ssh/webui password, else will be prompted
     -d N             enable debug trace level N (0 to 5)

Standalone:
     Create a file with individual standalone controllers, one per line

     example:
           mc01,1.2.3.4
           mc02,5.6.7.8



Installation
------------
Requires perl and a few modules which can be installed using CPAN (running the command-line: perl -eshell -MCPAN)

Following modules need to be installed:
LWP::Protocol::https
LWP::UserAgent
JSON
Date::Parse
Term::ReadKey

On non-Windows platforms:
Net::SSH::Perl
