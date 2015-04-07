package sgl_utils;
#
# Module is used by SGLBackup.pl and other soon to come scripts to have a central code place available.
# written in 2010-2015 by Sascha 'SieGeL' Pfalz <webmaster@saschapfalz.de>
#---------------------------------------------------------------------------
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#---------------------------------------------------------------------------
###################################################################################################
use strict;                                 # Report on all warnings
use vars qw( @ISA @EXPORT_OK);              # Make our special vars accessable
use Pod::Usage;                             # Used for command-line help
use Time::HiRes qw(gettimeofday);           # For measurements (transfer speeds etc.)
use File::Basename;                         # Filename manipulation
use Config::IniFiles;                       # Used to parse the config file
use IO::File;                               # For sysopen() constants

use Data::Dumper;

###################################################################################################
# Constant definitions
###################################################################################################

use constant SGL_UTILS_VERSION  => '0.16';   # Version of this package

###################################################################################################
# Exporter with important vars exported
###################################################################################################

use vars (qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS @AUXILIARY $LOGFILE $PATTERN_ACTIVE @ERRORS $_CFG));

BEGIN
  {
  require Exporter;
  @ISA         = qw(Exporter);
  @AUXILIARY   = qw(SGL_UTILS_VERSION

    ExecuteCMD
    FormatNumber
    getmicrotime
    trim
    SetLogfile
    WriteToLog
    PrintLog
    die_handler
    warn_handler
    ReadConfig
    ReadMySQLDBList
    createLockFile
    removeLockFile
    SendMail
    AddError
                     );
  @EXPORT      = @EXPORT;
  @EXPORT_OK   = (@EXPORT_OK,@AUXILIARY);
  %EXPORT_TAGS = (all => [@EXPORT_OK],
                  aux => [@AUXILIARY],
                  ALL => [@EXPORT_OK]);
  $VERSION        = SGL_UTILS_VERSION;
  $LOGFILE        = '';
  $PATTERN_ACTIVE = 0;             # Global flag is set to 1 if pattern are found
  $_CFG           = undef;
  }

END
  {
  if(defined($_CFG) && defined($_CFG->{'mail_cmd'}) && $_CFG->{'mail_cmd'} ne "")
    {
    if(scalar @ERRORS > 0)
      {
      my $hname = '';
      my $enum  = scalar @ERRORS;
      if(defined($ENV{'HOSTNAME'}))
        {
        $hname = sprintf("[%s]",$ENV{'HOSTNAME'});
        }
      else
        {
        $hname = '';
        }
      my $btext = sprintf("%d error(s) found while processing configuration file >%s< ! %s\n\n",$enum,$_CFG->{'cfg_filename'},$hname);
      for(my $i = 0; $i < $enum; $i++)
        {
        $btext.=$ERRORS[$i]."\n";
        }
      SendMail($_CFG,sprintf("SGLBackup: %d error(s) occured! %s",$enum,$hname),$btext);
      }
    }
  }

###################################################################################################
#    NAME: ExecuteCMD()
# PURPOSE: Executes a given commandline, and checks return result of command.
#   INPUT: $cmdline => The commandline to execute
#          $logname => Name to use in case of an error as prefix to the error commands
#          $cmd     => Name of program being called
#  RETURN: 0  => All okay, else a negative error number indicating the type of error
#          -1 => General error
#          -2 => Died with specific signal and possible coredump
#          -3 => Exited with exitvalue > 0
###################################################################################################

sub ExecuteCMD($$$)
  {
  my ($cmdline, $logname,$cmd) = @_;

  system($cmdline);
  if ($? == -1)
    {
    AddError(sprintf("%s FAILED!!!\nReason: %s\n\n",$logname,$!));
    WriteToLog(sprintf("ERROR: %s failed: %s",$logname,$!));
    return(-1);
    }
  elsif ($? & 127)
    {
    AddError(sprintf("%s FAILED!!!\n%s died with signal %d, %s coredump\n\n",$logname, $cmd, ($? & 127),  ($? & 128) ? 'with' : 'without'));
    WriteToLog(sprintf("ERROR: %s died with signal %d, %s coredump",$logname, ($? & 127),  ($? & 128) ? 'with' : 'without'));
    return(-2);
    }
  else
    {
    if(($? >> 8) > 0)
      {
      AddError(sprintf("%s FAILED!!!\n%s exited with value %d\n\n", $logname, $cmd, $? >> 8));
      WriteToLog(sprintf("ERROR: %s exited with value %d",$logname, $? >> 8));
      return(-3);
      }
    }
  return(0);
  }

###################################################################################################
#    NAME: FormatNumber
# PURPOSE: Formats numbers with grouping characters.
#   INPUT: None
#  RETURN: None
#    NOTE: Taken from Perl manual "perlfaq5".
###################################################################################################

sub FormatNumber
  {
  local $_  = shift;
  1 while s/^([-+]?\d+)(\d{3})/$1,$2/;
  return $_;
  }

###################################################################################################
#    NAME: getmicrotime
# PURPOSE: Determines seconds + microseconds. Used to measure processing speeds.
#   INPUT: None
#  RETURN: Float of current time in format sec.usec
###################################################################################################

sub getmicrotime
  {
  my ($sec,$usec) = gettimeofday;
  return(sprintf("%d.%d",$sec,$usec));
  }

###################################################################################################
#    NAME: trim
# PURPOSE: Simple trim() function...unbelievable that Perl does not supply such a trivial function...
#   INPUT: String or array from where to trim leading and trailing spaces
#  RETURN: Trimmed version of passed string or array
###################################################################################################

sub trim
  {
  my @out = @_;
  if(@_)
    {
    eval
      {
      for (@out)
        {
        if(defined($_))
          {
          s/^\s+//;
          s/\s+$//;
          }
        }
      };
    }
  return wantarray ? @out : $out[0];
  }

###################################################################################################
#    NAME: SetLogfile()
# PURPOSE: Sets the logfile path to internal package variable for further calls
#   INPUT: 0 => Complete filename to logfile
#        : 1 => Application info string
#  RETURN: None
###################################################################################################

sub SetLogfile($$)
  {
  my ($logfile,$appinfo) = @_;

  $self::LOGFILE = $logfile;
  WriteToLog(sprintf("------- Starting %s -------",$appinfo));
  }

###################################################################################################
#    NAME: WriteToLog()
# PURPOSE: General logging function
#   INPUT: Logstring to write
#  RETURN: None
###################################################################################################

sub WriteToLog($)
  {
  my ($logstring) = @_;

  my @tiarray = localtime (time());

  # If no logfile is defined we skip writing to log:
  if(!defined($self::LOGFILE) || $self::LOGFILE eq "")
    {
    return;
    }
  if($tiarray[5] > 70)
    {
    $tiarray[5]+=1900;
    }
  else
    {
    $tiarray[5]+=2000;
    }
  open(FH,">>".$self::LOGFILE) || die "Unable to write to $self::LOGFILE ?!";
  if(!defined($logstring)) { $logstring = ''; }
  $logstring=~s/^\n+//;
  $logstring=~s/\n+$//;
  my $buffer = sprintf("[%02d/%02d/%4d %02d:%02d:%02d][%5d]: %s\n",($tiarray[4]+1),$tiarray[3],$tiarray[5],$tiarray[2],$tiarray[1],$tiarray[0],$$,$logstring);
  print FH $buffer;
  close(FH);
  }

###################################################################################################
#    NAME: PrintLog()
# PURPOSE: General logging function
#   INPUT: Logstring to write
#  RETURN: None
###################################################################################################

sub PrintLog($)
  {
  my ($logstring) = @_;

  print $logstring;
  WriteToLog($logstring);
  }

###################################################################################################
#    NAME: warn_handler
# PURPOSE: Signal handler for warn() calls (routes to WriteToLog()
#   INPUT: None
#  RETURN: None
###################################################################################################

sub warn_handler
  {
  my $warntxt;
  my $showerr;

  $warntxt = join(', ',@_);
  $warntxt=~s/\n//g;
  $warntxt=~/(.*\s+)(at\s+)(.*)(\s+)(line\s+\d{0,}).*/;

  if(defined($3) && $3 ne '')
    {
    my $appname = basename($3);
    my $errline = $5;
    $showerr = sprintf("[%s: %s] W: %s",$appname,$errline,$1);
    }
  else
    {
    $showerr = "W: ".$warntxt;
    }
  AddError($showerr."\n");
  WriteToLog($showerr);
  }

###################################################################################################
#    NAME: die_handler
# PURPOSE: Signal handler for die() calls (adds date/time/file/linenumber):
#   INPUT: None
#  RETURN: None
#   NOTES: Catches die(), writes message to logfile and exits the script!
###################################################################################################

sub die_handler
  {
  my ($error) = @_;

  $error=~s/\n//g;
  $error=~/(.*\s+)(at\s+)(.*)(\s+)(line\s+\d{0,}).*/;

  if(defined($3) && $3 ne '')
    {
    my $appname = basename($3);
    my $errline = $5;
    my $showerr = sprintf("[%s: %s] D: %s",$appname,$errline,$1);
    WriteToLog($showerr);
    }
  die $error."\n\n";
  exit;
  }

###################################################################################################
#    NAME: ReadConfig()
# PURPOSE: Read and parse the configuration
#   INPUT: Configuration filename
#  RETURN: Hashref of parsed configuration
###################################################################################################

sub ReadConfig($)
  {
  my ($fname) = @_;
  my $cfg;
  my $config;
  my $i = 0;
  my $testparam;

  eval
    {
    $cfg = Config::IniFiles->new(-file => $fname, -nocase => 1) || die ( join("\n",  @Config::IniFiles::errors));
    $config->{'gzip'}         = trim($cfg->val('COMMAND','GZIP')) || die "Errors in $fname: No 'GZIP' tag defined!\n";
    $config->{'ext'}          = trim($cfg->val('COMMAND','GZIP_EXT')) || die "Errors in $fname: NO 'GZIP_EXT' tag defined!\n";
    $config->{'tar'}          = trim($cfg->val('COMMAND','TAR')) || die "Errors in $fname: No 'TAR' tag defined!\n";
    $config->{'taropts'}      = trim($cfg->val('COMMAND','TAROPTS'));
    $config->{'tmpdir'}       = trim($cfg->val('COMMAND','TMPDIR'));
    $config->{'logfile'}      = trim($cfg->val('COMMAND','LOGFILE'));
    $config->{'mysqldump'}    = trim($cfg->val('COMMAND','MYSQLDUMP'));
    $config->{'mysqldumpopts'}= trim($cfg->val('COMMAND','MYSQLDUMPOPTS'));
    $config->{'mknod'}        = trim($cfg->val('COMMAND','MKNOD'));
    $config->{'scp_bin'}      = trim($cfg->val('COMMAND','SCP_BIN'));
    $config->{'ssh_bin'}      = trim($cfg->val('COMMAND','SSH_BIN'));
    $config->{'mail_cmd'}     = trim($cfg->val('COMMAND','MAIL_CMD'));
    $config->{'host_desc'}    = trim($cfg->val('COMMAND','HOST_DESCRIPTION'));
    $config->{'cfg_filename'} = $fname;
    while(1)
      {
      $config->{'dir'}[$i]    = trim($cfg->val('BACKUP_SETS','DIR_'.$i)) || last;
      $config->{'name'}[$i]   = trim($cfg->val('BACKUP_SETS','NAME_'.$i));
      $config->{'mode'}[$i]   = trim(lc($cfg->val('BACKUP_SETS','MODE_'.$i)));
      $config->{'maxgen'}[$i] = trim($cfg->val('BACKUP_SETS','MAXGEN_'.$i));
      $config->{'dest'}[$i]   = trim($cfg->val('BACKUP_SETS','DEST_'.$i));
      $config->{'ftp'}[$i]    = trim($cfg->val('BACKUP_SETS','FTP_'.$i));
      $config->{'ftpdir'}[$i] = trim($cfg->val('BACKUP_SETS','FTP_DEST_'.$i));
      $config->{'scp'}[$i]    = trim($cfg->val('BACKUP_SETS','SCP_'.$i));
      $config->{'scpopts'}[$i]= trim($cfg->val('BACKUP_SETS','SCP_OPTS_'.$i));
      $config->{'sshopts'}[$i]= trim($cfg->val('BACKUP_SETS','SSH_OPTS_'.$i));
      $config->{'pattern'}[$i]= 0;
      $testparam = trim($cfg->val('BACKUP_SETS','VLDB_'.$i));
      if(!defined($testparam) || $testparam eq '' || uc($testparam) ne 'YES')
        {
        $config->{'vldb'}[$i] = 0;
        }
      else
        {
        $config->{'vldb'}[$i] = 1;
        }
      $testparam = trim($cfg->val('BACKUP_SETS','COMPRESS_'.$i));
      if(!defined($testparam) || $testparam eq '' || uc($testparam) ne 'NO')
        {
        $config->{'compress'}[$i] = 1;
        }
      else
        {
        $config->{'compress'}[$i] = 0;
        }
      # Since V0.43+
      $testparam = trim($cfg->val('BACKUP_SETS','EXCLUDE_'.$i));
      if(!defined($testparam) || $testparam eq '')
        {
        $config->{'exclude'}[$i] = undef;
        }
      else
        {
        @{$config->{'exclude'}[$i]} = split(/,/,$testparam);
        }

      my @test = split(/,/,$config->{'mode'}[$i]);
      for(my $a =0; $a < scalar @test; $a++)
        {
        if($test[$a] eq 'fcopy' && ( !defined($config->{'dest'}[$i]) || $config->{'dest'}[$i] eq ''))
          {
          die("CFG-ERROR: BackupSet #$i has FCOPY mode defined but no destination set!");
          }
        if($test[$a] eq 'ftp')
          {
          if(!defined($config->{'ftp'}[$i]) || $config->{'ftp'}[$i] eq '')
            {
            die("CFG-ERROR: BackupSet #$i has FTP mode defined but no FTP data given!!");
            }
          $config->{'ftp'}[$i]=~/(.*)(\:)(.*)(@)(.*)/;
          my $ftpuser = (defined($1)) ? $1 : '';
          my $ftppass = (defined($3)) ? $3 : '';
          my $ftphost = (defined($5)) ? $5 : '';
          if($ftpuser eq '' || $ftppass eq '' || $ftphost eq '')
            {
            die(sprintf("CFG-ERROR: FTP settings wrong for backupset #%d (%s)",$i,$config->{'name'}[$i]));
            }
          }
        if($test[$a] eq 'scp')
          {
          if(!defined($config->{'scp'}[$i]) || $config->{'scp'}[$i] eq '')
            {
            die("CFG-ERROR: BackupSet #$i has SCP mode defined but no SCP data given!!");
            }
          if(!defined($config->{'sshopts'}[$i]) || $config->{'sshopts'}[$i] eq '')
            {
            die("CFG-ERROR: BackupSet #$i has SCP mode defined but no SSH data given!!");
            }
          $config->{'scp'}[$i]=~/(.*)(@)(.*)(\:)(.*)/;
          my $scpuser = (defined($1)) ? $1 : '';
          my $scphost = (defined($3)) ? $3 : '';
          my $scp_dir = (defined($5)) ? $5 : '';
          if($scpuser eq '' || $scphost eq '' || $scp_dir eq '')
            {
            die(sprintf("CFG-ERROR: SCP settings wrong for backupset #%d (%s)",$i,$config->{'name'}[$i]));
            }
          }
        }
      $i++;
      undef($testparam);
      }
    };
  $config->{'maxsets'} = $i;
  if($@)
    {
    $@=~s/(.*)(at.*)/$1/g;
    chop($@);
    die (sprintf("%s\n\n",$@));
    }
  if($config->{'tmpdir'} eq '')
    {
    $config->{'tmpdir'} = '/tmp';
    }
  if(!-X $config->{'tar'})
    {
    die (sprintf("CFG: '%s' is not executable!!\n\n",$config->{'tar'}));
    }
  my @testfile = split(/ /,$config->{'gzip'});
  if(!-X $testfile[0])
    {
    die (sprintf("CFG: '%s' is not executable!!\n\n",$testfile[0]));
    }
  # V0.50: Check for known extensions, currently only bz2 and gz are known:
  if($config->{'ext'} eq '.bz2')
    {
    $config->{'tar_opt'} = 'j';
    }
  elsif($config->{'ext'} eq '.gz')
    {
    $config->{'tar_opt'} = 'z';
    }
  else
    {
    die(sprintf("CFG: Unknown extension \"%s\" specified, only .gz or .bz2 are supported!\n\n",$config->{'ext'}));
    }

  if(defined($config->{'mysqldump'}))
    {
    if(!-X $config->{'mysqldump'})
      {
      die(sprintf("CFG: '%s' not found / not executable!!!\n\n",$config->{'mysqldump'}));
      }
    }
  if(!defined($config->{'taropts'}) || $config->{'taropts'} eq '')
    {
    $config->{'taropts'} = '-ch'.$config->{'tar_opt'}.'f';
    }
  else
    {
    # V0.50: Check if last parameter is 'f', die() if not (required for correct operation of tar!)
    if(substr($config->{'taropts'},-1) ne 'f')
      {
      die(sprintf("CFG: TAROPTS Parameter has no 'f' value as last config option set [%s]",$config->{'taropts'}));
      }
    $config->{'taropts'} = substr(trim($config->{'taropts'}),0,length($config->{'taropts'})-1).$config->{'tar_opt'}.'f';
    }
  if(!defined($config->{'mysqldumpopts'}))
    {
    $config->{'mysqldumpopts'} = '';
    }
  if(defined($config->{'mknod'}))
    {
    if(!-X $config->{'mknod'})
      {
      die(sprintf("CFG: '%s' not found / not executable!!!\n\n",$config->{'mknod'}));
      }
    }
  # 0.14: Check if host_description is set
  if(!defined($config->{'host_desc'}))
    {
    $config->{'host_desc'} = `uname -n`;
    }

  my $newmaxsets = $config->{'maxsets'};
  for(my $i = 0; $i < $config->{'maxsets'}; $i++)
    {
    if($config->{'dir'}[$i]=~/\*$/)
      {
      $PATTERN_ACTIVE = 1;
      $config->{'pattern'}[$i] = 1;       # Mark entry, so that we do not try to backup THIS entry
      my ($mysqldb,$mysqlhost,$mysqluser,$mysqlpass,$mysqllocal);
      if($config->{'dir'}[$i]=~/^MYSQL\:/ || $config->{'dir'}[$i]=~/^MYSQL56\+\:/)
        {
        # Parse old MySQL style with password on commandline
        if($config->{'dir'}[$i]=~/^MYSQL\:/)
          {
          $mysqllocal = '';
          my @dummy = split /\|/,$config->{'dir'}[$i];
          if(defined($dummy[1]) && $dummy[1] ne '')
            {
            $mysqldb = $dummy[1];
            }
          $dummy[0]=~s/^MYSQL://;
          my @dummy2 = split /\@/,$dummy[0];
          if(defined($dummy2[1]) && $dummy2[1] ne '')
            {
            $mysqlhost = $dummy2[1];
            }
          else
            {
            $mysqlhost = "localhost";
            }
          @dummy2 = split(/\//, $dummy2[0]);
          $mysqluser = $dummy2[0];
          if(!defined($mysqluser) || $mysqluser eq '')
            {
            printf(STDERR "ReadConfig() FAILED!!!\n\nCannot determine MySQL User name for backupset %s (Defined was %s) ????\n\n",$i,$config->{'dir'}[$i]);
            die ("Check configuration of listed backupset - Aborting\n");
            }
          $mysqlpass = (defined($dummy2[1]) ? $dummy2[1] : '');
          # Make pattern useable under perl (simple * is not enough)
          if($mysqldb eq '*')
            {
            $mysqldb = '.*';
            }
          else
            {
            $mysqldb=~s/\*/\.\*/;
            }
          }
        else
          {
          # New format for MySQL 5.6 or neweR:
          # MYSQL56+: <username>/<local-path_value>|database
          my @dummy = split /\|/,$config->{'dir'}[$i];
          if(defined($dummy[1]) && $dummy[1] ne '')
            {
            $mysqldb = $dummy[1];
            }
          if($mysqldb eq '*')
            {
            $mysqldb = '.*';
            }
          else
            {
            $mysqldb=~s/\*/\.\*/;
            }
          $dummy[0]=~s/^MYSQL56\+://;
          my @dummy2 = split /\@/,$dummy[0];
          @dummy2 = split(/\//, $dummy2[0]);
          $mysqluser = $dummy2[0];
          if(!defined($mysqluser) || $mysqluser eq '')
            {
            printf(STDERR "ReadConfig() FAILED!!!\n\nCannot determine MySQL User name for backupset %s (Defined was %s) ????\n\n",$i,$config->{'dir'}[$i]);
            die ("Check configuration of listed backupset - Aborting\n");
            }
          $mysqllocal = (defined($dummy2[1]) ? $dummy2[1] : '');
          }
        my @dbs = ReadMySQLDBList($mysqluser,$mysqlpass,$mysqlhost,$mysqldb,$config->{'mysqldump'},$config->{'tmpdir'},$mysqllocal);
        # Now add the new found directories as new entries to our config array
        for(my $jobs = 0; $jobs < scalar @dbs; $jobs++)
          {
          if($mysqllocal ne '')
            {
            $config->{'dir'}[$newmaxsets]     = sprintf("MYSQL56+:%s/%s|%s",$mysqluser,$mysqllocal,$dbs[$jobs]);
            }
          else
            {
            $config->{'dir'}[$newmaxsets]     = sprintf("MYSQL:%s/%s@%s|%s",$mysqluser,$mysqlpass,$mysqlhost,$dbs[$jobs]);
            }
          $config->{'name'}[$newmaxsets]    = $config->{'name'}[$i]."_".$dbs[$jobs];
          $config->{'mode'}[$newmaxsets]    = $config->{'mode'}[$i];
          $config->{'maxgen'}[$newmaxsets]  = $config->{'maxgen'}[$i];
          $config->{'dest'}[$newmaxsets]    = $config->{'dest'}[$i];
          $config->{'ftp'}[$newmaxsets]     = $config->{'ftp'}[$i];
          $config->{'ftpdir'}[$newmaxsets]  = $config->{'ftpdir'}[$i];
          $config->{'vldb'}[$newmaxsets]    = $config->{'vldb'}[$i];
          $config->{'pattern'}[$newmaxsets] = 0;
          $config->{'compress'}[$newmaxsets]= $config->{'compress'}[$i];
          $config->{'scp'}[$newmaxsets]     = $config->{'scp'}[$i];
          $config->{'scpopts'}[$newmaxsets] = $config->{'scpopts'}[$i];
          $config->{'sshopts'}[$newmaxsets] = $config->{'sshopts'}[$i];
          $config->{'exclude'}[$newmaxsets] = $config->{'exclude'}[$i];
          $config->{'muser'}[$newmaxsets]   = $mysqluser;
          $config->{'mpass'}[$newmaxsets]   = $mysqlpass;
          $config->{'mhost'}[$newmaxsets]   = $mysqlhost;
          $config->{'mdb'}[$newmaxsets]     = $mysqldb=$dbs[$jobs];
          $config->{'mlocal'}[$newmaxsets]  = $mysqllocal;
          $newmaxsets++;
          }
        }
      else
        {
        my @entries;
        my $targetdir = $config->{'dir'}[$i];
        my $pattern;
        my $destpattern     = 0;
        my $ftpdestpattern  = 0;
        $pattern   = substr($config->{'dir'}[$i],(rindex $config->{'dir'}[$i],"/")+1);
        $targetdir = substr($targetdir,0,rindex $targetdir,"/");
        # Avoid perl warning because * matches also NULL strings?! ...whatever that means ;)
        if($pattern eq '*')
          {
          $pattern = '.*';
          }
        else
          {
          $pattern=~s/\*/\.\*/;
          }
        if(defined($config->{'dest'}[$i]) && $config->{'dest'}[$i]=~/\*$/)
          {
          $destpattern = 1;
          }
        if(defined($config->{'ftpdir'}[$i]) && $config->{'ftpdir'}[$i]=~/\*$/)
          {
          $ftpdestpattern = 1;
          }
        opendir THISDIR, $targetdir || die "cannot open ".$config->{'dir'}[$i]." for reading pattern based directory!\n";
        my @files = readdir THISDIR;
        close THISDIR;
        @entries = grep !/^\.\.?$/,@files;              # Remove Dot files
        @entries = grep /^$pattern/,@entries;           # Remove everything else not matching our pattern
        @entries = grep -d "$targetdir/$_", @entries;   # Remove everything NOT a directory
        if(defined($config->{'exclude'}[$i]))
          {
          my $expat = join("|",@{$config->{'exclude'}[$i]});
          @entries  = grep !/^$expat/,@entries;
          }
        @entries = sort @entries;
        # Now add the new found directories as new entries to our config array
        for(my $jobs = 0; $jobs < scalar @entries; $jobs++)
          {
          $config->{'dir'}[$newmaxsets]     = $targetdir."/".$entries[$jobs];
          $config->{'name'}[$newmaxsets]    = $config->{'name'}[$i]."_".$entries[$jobs];
          $config->{'mode'}[$newmaxsets]    = $config->{'mode'}[$i];
          $config->{'maxgen'}[$newmaxsets]  = $config->{'maxgen'}[$i];
          if($destpattern)
            {
            my $ddir = $config->{'dest'}[$i];
            $ddir=~s/(.*)(\*)/$1/;
            $ddir=~s/\/$//;
            $config->{'dest'}[$newmaxsets]  = $ddir.'/'.$entries[$jobs];
            $config->{'createdest'}[$newmaxsets] = 1;
            }
          else
            {
            $config->{'dest'}[$newmaxsets]    = $config->{'dest'}[$i];
            $config->{'createdest'}[$newmaxsets] = 0;
            }
          $config->{'ftp'}[$newmaxsets]     = $config->{'ftp'}[$i];
          if($ftpdestpattern)
            {
            my $ftpdir = $config->{'ftpdir'}[$i];
            $ftpdir=~s/(.*)(\*)/$1/;
            $ftpdir=~s/\/$//;
            $config->{'ftpdir'}[$newmaxsets]  = $ftpdir.'/'.$entries[$jobs];
            $config->{'createftpdir'}[$newmaxsets] = 1;
            }
          else
            {
            $config->{'ftpdir'}[$newmaxsets]  = $config->{'ftpdir'}[$i];
            $config->{'createftpdir'}[$newmaxsets] = 0;
            }
          $config->{'vldb'}[$newmaxsets]    = $config->{'vldb'}[$i];
          $config->{'pattern'}[$newmaxsets] = 0;
          $config->{'compress'}[$newmaxsets]= $config->{'compress'}[$i];
          $config->{'scp'}[$newmaxsets]     = $config->{'scp'}[$i];
          $config->{'scpopts'}[$newmaxsets] = $config->{'scpopts'}[$i];
          $config->{'sshopts'}[$newmaxsets] = $config->{'sshopts'}[$i];
          $config->{'exclude'}[$newmaxsets] = $config->{'exclude'}[$i];
          $newmaxsets++;
          }
        }
      }
    }
  $config->{'maxsets'} = $newmaxsets;
  $_CFG = $config;
  # TO-DO: Check configured directories for accessability!
  return($config);
  }

###################################################################################################
#    NAME: ReadMySQLDBList()
# PURPOSE: Reads available databases from given MySQL DB, matches them against the pattern and
#          returns an array of database names which will be added to our internal config list
#   INPUT: $muser   => Username for MySQL, must have access to the "SHOW DATABASES" command!
#          $mpass   => Password of the given user
#          $mhost   => Hostname to connect
#          $mdb     => Pattern to use against the list of available databases
#          $mdump   => Full path to mysqldump util from configuration
#          $tmpdir  => Path to temporary directory
#          $mlocal  => If given, use this for new connection method (MySQL 5.6+)
#  RETURN: Array of found databases or undef in case of an error
#   NOTES: We assume here that the MYSQL tool "mysql" can be found under the same location
#          as the MySQLDump command. if this is not the case we abort here with an appropiate
#          error message.
#          mysql --user=<user> --password=<pass> --host=<host> --vertical --execute="show databases"
#          New method "MYSQL56+" requires to have the password created by the new MySQL command:
#          mysql_config_editor set --login-path=local --host=localhost --user=db_user --password
####################################################################################################

sub ReadMySQLDBList($$$$$$$)
  {
  my ($muser,$mpass,$mhost,$mdb,$mdump,$tmpdir,$mlocal) = @_;
  my $commandline = '';
  my @resultarray;

  if(!defined($mdump) || $mdump eq '')
    {
    AddError("ERROR: No MySQLDump utility configured - MySQL support is disabled!!!\n");
    exit 10;
    }
  my $mtool = dirname($mdump)."/mysql";
  if(!-X $mtool)
    {
    AddError(sprintf("ERROR: mysql utility under %s is not executable!!!\n",$mtool));
    exit 10;
    }
  my $tmpname = sprintf("%s/dblist_%s.lst",$tmpdir,$$);
  # 0.45: Check if we are using login-path instead of password
  if($mlocal ne '')
    {
    $commandline = sprintf("%s --login-path=%s --user=%s --vertical --execute=\"show databases\" >%s",$mtool,$mlocal,$muser,$tmpname);
    }
  else
    {
    if($mpass eq '')
      {
      $commandline = sprintf("%s --user=%s --host=%s --vertical --execute=\"show databases\" >%s",$mtool,$muser,$mhost,$tmpname);
      }
    else
      {
      $commandline = sprintf("%s --user=%s --password=%s --host=%s --vertical --execute=\"show databases\" >%s",$mtool,$muser,$mpass,$mhost,$tmpname);
      }
    }
  if(ExecuteCMD($commandline,"ReadMySQLDBList()->mysql",$mtool))
    {
    unlink($tmpname);
    die();
    }
  # Now read and parse the temporary file extracting the MySQL Database names:
  open(FH, $tmpname) || die "ReadMySQLDBList(): Unable to read temporary database list file?!";
  while(<FH>)
    {
    if($_ =~/^database.*/i)
      {
      my $data = $_;
      $data=~/(^database\:\s)(.*)/i;
      my $dbname = $2;
      # V0.42: Skip database if information_schema db is found (MySQL data dictionary)
      if($dbname ne 'information_schema' && $dbname ne 'performance_schema')
        {
        push @resultarray,$dbname;
        }
      }
    }
  close(FH);
  unlink($tmpname);
  my @entries = grep /^$mdb/,@resultarray;
  return(sort @entries);
  }

####################################################################################################
#    NAME: CreateLockFile()
# PURPOSE: Tries to create a lockfile based on passed config name.
#   INPUT: $1 => Name of configuration file.
#  RETURN: 0 = Lockfile was created, else 1
####################################################################################################
sub createLockFile($)
  {
  my ($cname) = @_;
  my $exists = 0;
  my $fname = '/tmp/'.$cname.'.lck';

  sysopen(FH, $fname, O_WRONLY|O_EXCL|O_CREAT) or $exists = 1;
  if($exists == 1)
    {
    open FH, $fname;
    my $buf = <FH>;
    close(FH);
    return($buf);
    }
  printf(FH "%d",$$);
  close(FH);
  return(0);
  }

####################################################################################################
#    NAME: CreateLockFile()
# PURPOSE: Tries to create a lockfile based on passed config name.
#   INPUT: $1 => Name of configuration file.
#  RETURN: 0 = Lockfile was created, else 1
####################################################################################################
sub removeLockFile($)
  {
  my ($cname) = @_;

  my $fname = '/tmp/'.$cname.'.lck';
  unlink $fname;
  }

###################################################################################################
#     NAME: SendMail()
#  PURPOSE: Function sends E-Mails.
#    INPUT: 1 => config hash
#           2 => Subject of email
#           3 => Body text
#   RETURN: None
###################################################################################################

sub SendMail($$$)
  {
  my ($cfg,$subject,$bodytext) = @_;
  if(!defined($cfg->{'mail_cmd'}) || $cfg->{'mail_cmd'} eq "")
    {
    return;
    }
  $bodytext = "HOST: ".$cfg->{'host_desc'}."\n\n".$bodytext;
  my $cmd = $cfg->{'mail_cmd'};
  $cmd=~s/{SUBJECT}/$subject/;
  $cmd=~s/{BODY_TEXT}/$bodytext/;
  ExecuteCMD($cmd,'SendMail',$cfg->{'mail_cmd'});
  }

###################################################################################################
#     NAME: AddError()
#  PURPOSE: Adds error message to internal array @ERRORS and also prints this message on STDERR.
#    INPUT: 1 => The text to add/print
###################################################################################################
sub AddError($)
  {
  my ($emsg) = @_;
  printf(STDERR $emsg);
  $emsg=~s/\n//;
  push @ERRORS, $emsg;
  }

###################################################################################################
# Required for Perl (true return)
###################################################################################################

1;

__END__

=head1 NAME

sgl_utils.pm - Perl support module for SGLBackup and friends.

=head1 SYNOPSIS

use sgl_utils qw(:all);

=head1 OPTIONS

=head1 AUTHOR

Sascha 'SieGeL' Pfalz <webmaster@saschapfalz.de>E<10>

=head1 VERSION

This is sgl_utils.pm V0.16

=head1 HISTORY

=over 2

=item <Bv0.16 (07-Apr-2015)>

Added check for known packer extensions, currently only .gz and .bz2 are allowed. This is used to tar and pack in one step using the correct modifier.

=item <Bv0.15 (29-Mar-2015)>

Added support for new "MYSQL56+" format, which utilize the --login-path Parameter of MySQL 5.6+ instead of using passwords on command-line.

=item <Bv0.14 (23-Feb-2014)>

Added support for new parameter "HOST_DESCRIPTION" in SendMail().

=item B<v0.12 (12-Aug-2012)>

Added support for wildcards in target directories.

=item B<v0.11 (27-Aug-2011)>

Added "SendMail()" function which triggers the sending of warning emails, if a MAIL_CMD is configured.

Added Locking functions "createLockFile()" and "removeLockFile()" to prevent double starts.

=item B<V0.1 (10-Oct-2010)>

Initial release of this package. As their are some plans to add more helper scripts,
this package was born to make it easier to share the various code parts.

=back

=cut
