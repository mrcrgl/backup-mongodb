#!/usr/bin/perl -w

use Config::IniFiles;
use Date::Format;
use strict;
use warnings;

our $VERSION = '0.1.0';

usage_and_exit("Missing [configuration]\n") unless $ARGV[0];
usage_and_exit("[action] not implemented\n") unless $ARGV[1] && $ARGV[1] =~ /^(backup|restore)$/;
if ($ARGV[1] eq 'restore') {
    usage_and_exit("Missing [day] to restore\n") unless $ARGV[2] =~ /^([0-9]{4})-([0-9]{2})-([0-9]{2})$/;
}


my $ConfigSlug = $ARGV[0];
my $Action = $ARGV[1] || 'backup';
my $DayToRestore = $ARGV[2] || undef;
our @ConfigPaths = qw(~/backup-mongodb ~/.mongo-backup .);

our $Config = load_configuration($ConfigSlug);

usage_and_exit("Invalid configuration.") unless ($Config);

our @Binaries = qw(mongodump tar find);
foreach (@Binaries) {
    usage_and_exit(sprintf("Missing binary: %s\n", $_)) unless `which $_`;
}

our $BackupCacheDir = $Config->val('Plan', 'BackupCacheDir');
$BackupCacheDir =~ s/~/$ENV{"HOME"}/;
unless (-d $BackupCacheDir) {
    die printf "%s\n", $! unless mkdir($BackupCacheDir);
}

our $BackupDir = $Config->val('Plan', 'BackupDir');
$BackupDir =~ s/~/$ENV{"HOME"}/;
unless (-d $BackupDir) {
    die sprintf "%s\n", $! unless mkdir($BackupDir);
}

if ($Action eq 'backup') {
    &backup();
} elsif ($Action eq 'restore') {
    &restore($DayToRestore);
}


### methods ###

sub backup {
    my ($TempSize, $TargetSize, $Compression) = 0;
    
    my $TempFolder = sprintf("%s/%s", $BackupCacheDir, time2str("%Y-%m-%d", time));
    mkdir($TempFolder) unless (-d $TempFolder);
    
    my $TargetFile = sprintf("%s/%s.tbz2", $BackupDir, time2str("%Y-%m-%d", time));
    
    die("File exists: " . $TargetFile) if (-f $TargetFile);
    
    print "--- START " . localtime() . " ---\n";
    
    print "Export...";
    
    system(
        sprintf(
            "mongodump --out %s %s %s %s %s > /dev/null", 
            $TempFolder,
            ($Config->val('Creds', 'Username')) ? sprintf("-u %s", $Config->val('Creds', 'Username')) : '',
            ($Config->val('Creds', 'Password')) ? sprintf("-p %s", $Config->val('Creds', 'Password')) : '',
            ($Config->val('Creds', 'Host')) ? sprintf("-h %s", $Config->val('Creds', 'Host')) : '',
            ($Config->val('Creds', 'Port')) ? sprintf("--port %s", $Config->val('Creds', 'Port')) : ''
        )
    );
    $TempSize = `du -sk $TempFolder | awk '{print \$1}'`;
    $TempSize =~ s/\W//;
    
    printf "done. (%sk)\n", $TempSize;
    print "Compress...";
    
    system( sprintf("cd %s && tar cjpf %s . > /dev/null", $TempFolder, $TargetFile) );
    $TargetSize = `du -sk $TargetFile | awk '{print \$1}'`;
    $TargetSize =~ s/\W//;
    
    printf "done. (%sk / Compression: %s%%)\n", $TargetSize, 100/$TempSize*($TempSize-$TargetSize);
    print "Remove temp...";
    
    system( sprintf("rm -rf %s", $TempFolder) );
    
    print "done.\n";
    #system( sprintf("find %s -name *.tbz2 -type f -ctime -14 -exec rm {} \;", $BackupDir) );
    
    print "Backup saved to: " . $TargetFile . "\n";
    print "--- FINISHED " . localtime() . " ---\n";
}

sub restore {
    print "Not implemented yet.";
}

sub load_configuration {
    my $ConfigSlug = shift || usage_and_exit();
    
    my $Defaults = load_configuration('defaults') unless $ConfigSlug eq 'defaults';
    
    foreach my $Path (@ConfigPaths) {
        my $File = sprintf("%s/%s.ini", $Path, $ConfigSlug);
        next unless (-f $File);
        
        my $Cfg = Config::IniFiles->new( 
            (($Defaults) ? (-file => $File, -import => $Defaults) : (-file => $File))
        );
        if (@Config::IniFiles::errors > 0) {
            my $errors = "";
            foreach (@Config::IniFiles::errors) {
                $errors .= sprintf("%s\n", $_);
            }
            
            usage_and_exit($errors);
        } else {
            return $Cfg;
        }
        
    }
    
}

sub usage_and_exit {
    my $errors = shift || 0;
    
    printf "%s\n", $errors if $errors;
    printf "%s [configuration]\n", $0;
    printf "Version: %s\n\n", $VERSION;
    
    exit(0);
}