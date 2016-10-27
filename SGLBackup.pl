#!/usr/bin/perl -w
#
# This Script takes directories out of a config file,
# tars them and copies the tared and zipped files over
# various locations configurable via an external config file.
# Call it with "./SGLBackup.pl --man" to get build-in manual.
#
# written by Sascha 'SieGeL' Pfalz <webmaster@saschapfalz.de>
#---------------------------------------------------------------------------
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#---------------------------------------------------------------------------
###################################################################################################

use strict;                         # Enforce all warnings
use Getopt::Long;                   # Used for command-line parsing
use Pod::Usage;                     # Used for command-line help
use Time::HiRes qw(gettimeofday);   # For measurements (transfer speeds etc.)
use Net::FTP;                       # FTP Backup support
use File::Copy;                     # Filecopy/Move functions
use File::Basename;                 # Filename manipulation
use File::Temp qw/ tempfile /;      # Temp filename generation
use Data::Dumper;                   # Useful for debugging
use sgl_utils qw(:all);             # Load in the global functions

###################################################################################################
# Global Variables
###################################################################################################

use constant VER => '0.52';         # Version of this script
my %bd;                             # Backup Dirs, stored as DIR_0/NAME_0 pairs
my $cfgfile = 'config.ini';         # Config filename, can be changed via --config=<> parameter
my $cfg;                            # Configuration settings stored as hash ref
my $bsets   = '-1';                 # Which backupset to process. (-1 process all)
use constant MODE_FCOPY   => 0;     # Mode FCOPY
use constant MODE_FTP     => 1;     # Mode FTP
use constant MODE_SCP     => 2;     # Mode SCP (V0.41+)
use constant CALL_CMD     => 0;     # CheckGen is called via Commandline
use constant CALL_BAK     => 1;     # CheckGen is called after Backups
use constant FTP_TIMEOUT  => 30;    # FTP Connect timeout in seconds

###################################################################################################
# Prototypes
###################################################################################################

sub main();                         # Main entry of this script
sub ShowConfigAndExit;              # Displays parsed configuration
sub TarAndZipSet($);                # Creates the backup file
sub ProcessBackup($$);              # Either filecopy or FTP the backup file and removes it from temp
sub ExportOracle($);                # Allows to export an oracle schema or complete database
sub ExportMySQL($);                 # Exports MySQL Databases
sub CheckGenerations($$);           # Performs check on available generations for a given backupset
sub ReadFileCopies($$);             # Reads available backups from filesystem
sub UploadFTP($$$$$);               # Upload to a given FTP server
sub ReadFTPCopies($);               # Reads available backups from FTP server
sub RemoveFTPFiles($$@);            # Removes list of files from FTP server
sub UploadSCP($$);                  # Upload to given SCP server
sub ReadSCPCopies($);               # Reads existing backup files from SCP server via SSH
sub RemoveSCPFiles($$@);            # Removes list of files from SCP server

###################################################################################################
# Start of script
###################################################################################################

$SIG{__WARN__}  = \&warn_handler;   # Install warn/die handlers
$SIG{__DIE__}   = \&die_handler;
my $mainst = getmicrotime;
$|=1;
my $rc = main();
my $mainet = getmicrotime;
printf("Total time required: %2.3fs\n\n",abs($mainet-$mainst));
WriteToLog(sprintf("------- Everything done, total time required: %2.3fs -------",abs($mainet-$mainst)));
exit $rc;

###################################################################################################
#    NAME: main()
# PURPOSE: Main entry of script, handles all processing
#   INPUT: None
#  RETURN: None
###################################################################################################

sub main()
  {
  my $help      = 0;  # Set to 1 if --help is choosen
  my $man       = 0;  # Set to 1 if --man is choosen
  my $showcfg   = 0;  # Set to 1 if --showconfig is choosen
  my $checkgen  = 0;  # Set to 1 if --checkgen is choosen
  my $backfile;

  printf("\nSGLBackup v%s written by Sascha 'SieGeL' Pfalz\n\n",VER);
  GetOptions ('help|?'          => \$help,
              'man'             => \$man,
              'config|f=s'      => \$cfgfile,
              'backupset|b=s'   => \$bsets,
              'showconfig|d'    => \$showcfg,
              'checkgen|cg'     => \$checkgen ) or pod2usage(2);
  pod2usage(1) if $help;
  pod2usage(-exitstatus => 0, -verbose => 2) if $man;
  $cfg = ReadConfig($cfgfile);
  if(!defined($cfg))
    {
    exit 10;
    }

  SetLogfile($cfg->{'logfile'},sprintf("SGLBackup %s",VER));

  # Now make sure that in pattern matching mode the user did not specify
  # a specific set, as this won't work as expected:

  if($sgl_utils::PATTERN_ACTIVE && ($bsets ne '-1' && $bsets ne ''))
    {
    PrintLog("You cannot specify specific backupsets when patterns are used!\nPlease refer to the documentation to learn why this is not allowed.\n\n");
    return(10);
    }

  # Create lockfile to prevent double starts of this script
  my $chk = createLockFile($cfgfile);
  if( $chk != 0)
    {
    PrintLog(sprintf("\nAn instance of SGLBackup (PID=%d) is already running - aborting 2nd start!\n\n",$chk));
    AddError(sprintf("An instance of SGLBackup (PID=%d) is already running - aborting 2nd start!\n",$chk));
    return(1);
    }

  # Check if user wants to see the configuration list:
  if($showcfg)
    {
    ShowConfigAndExit();
    WriteToLog(sprintf("Show configuration from file \"%s\"",$cfgfile));
    removeLockFile($cfgfile);
    return(0);
    }

  #
  # Test if user wants to check available generations via commandline
  # Note that we perform this of course also after backups are made, this
  # is here to manually perform this only!
  #

  if($checkgen)
    {
    if($bsets eq '-1')
      {
      for(my $i = 0; $i < $cfg->{'maxsets'}; $i++)
        {
        CheckGenerations($i,CALL_CMD);
        }
      }
    else
      {
      my @params = split(/,/,$bsets);
      for(my $i = 0; $i < scalar @params; $i++)
        {
        if($params[$i] < 0 || $params[$i] > $cfg->{'maxsets'}-1)
          {
          AddError(sprintf("ERROR: Set number \"%s\" is out of range (Allowed is 0-%d)!\n\n",$params[$i],$cfg->{'maxsets'}-1));
          removeLockFile($cfgfile);
          return(10);
          }
        }
      for(my $i = 0; $i < scalar @params; $i++)
        {
        CheckGenerations($params[$i],CALL_CMD);
        }
      }
    print("\n");
    removeLockFile($cfgfile);
    return(0);
    }

  #
  # Perform the backup tasks, either complete or for selected backupsets
  #

  if($bsets eq '-1')
    {
    printf("Starting backup of all %d sets, please wait.\n\n",$cfg->{'maxsets'});
    WriteToLog("--- Starting backup of all ".$cfg->{'maxsets'}." backupsets. ---");
    for(my $i = 0; $i < $cfg->{'maxsets'}; $i++)
      {
      if($cfg->{'dir'}[$i] ne '')
        {
        $backfile = TarAndZipSet($i);
        if(defined($backfile) && $backfile ne '')
          {
          ProcessBackup($backfile,$i);
          CheckGenerations($i,CALL_BAK);
          }
        }
      }
    }
  else
    {
    my @params = split(/,/,$bsets);
    for(my $i = 0; $i < scalar @params; $i++)
      {
      if($params[$i] < 0 || $params[$i] > $cfg->{'maxsets'}-1)
        {
        AddError(sprintf("ERROR: Set number \"%s\" is out of range (Allowed is 0-%d)!\n\n",$params[$i],$cfg->{'maxsets'}-1));
        removeLockFile($cfgfile);
        return(10);
        }
      }
    for(my $i = 0; $i < scalar @params; $i++)
      {
      $backfile = TarAndZipSet($params[$i]);
        if(defined($backfile) && $backfile ne '')
        {
        ProcessBackup($backfile,$params[$i]);
        CheckGenerations($params[$i],CALL_BAK);
        }
      }
    }
  removeLockFile($cfgfile);
  return(0);
  }

###################################################################################################
#    NAME: ShowConfigAndExit
# PURPOSE: Lists the parsed configuration. Useful to check if everything is correctly
#          configured before using SGLBackup via cronjob. (V0.33+)
#   INPUT: None
#  RETURN: None
###################################################################################################

sub ShowConfigAndExit
  {
  my $target;

  print("Show configuration:\n\n");
  printf("TAR program (Options)....: %s %s\n",$cfg->{'tar'},$cfg->{'taropts'});
  printf("Packer program...........: %s\n",$cfg->{'gzip'});
  printf("Packer extension.........: %s\n",$cfg->{'ext'});
  printf("Temporary directory......: %s\n",$cfg->{'tmpdir'});
  printf("Logfile to write.........: %s\n",(defined($cfg->{'logfile'})      ? $cfg->{'logfile'} : 'No logfile configured'));
  printf("ORACLE_HOME available....: %s\n",(defined($ENV{'ORACLE_HOME'})    ? 'Yes' : 'No'));
  printf("mysqldump utility........: %s\n",(defined($cfg->{'mysqldump'})    ? $cfg->{'mysqldump'} : 'Not available'));
  printf("mysqldump options........: %s\n",$cfg->{'mysqldumpopts'});
  printf("mknod utility............: %s\n",(defined($cfg->{'mknod'})        ? $cfg->{'mknod'} : 'Not available'));
  printf("scp utility..............: %s\n",(defined($cfg->{'scp_bin'})      ? $cfg->{'scp_bin'} : 'Not available'));
  printf("ssh utility..............: %s\n",(defined($cfg->{'ssh_bin'})      ? $cfg->{'ssh_bin'} : 'Not available'));
  printf("Mail command.............: %s\n",(defined($cfg->{'mail_cmd'})     ? $cfg->{'mail_cmd'} : 'Not configured'));
  printf("Number of backupsets.....: %d\n",$cfg->{'maxsets'});
  print("\nConfigured backup sets:\n\n");

  for(my $i = 0; $i < $cfg->{'maxsets'}; $i++)
    {
    printf("Backupset number (name)......: %d (%s)\n",$i, $cfg->{'name'}[$i]);
    printf("Backup source................: %s\n",$cfg->{'dir'}[$i]);
    print ("Excluding from source........: ");
    if(!defined($cfg->{'exclude'}[$i]))
      {
      print("-/-\n");
      }
    else
      {
      print(join(", ",@{$cfg->{'exclude'}[$i]})."\n");
      }
    $target = "";
    my @test = split(/,/,$cfg->{'mode'}[$i]);
    for(my $a =0; $a < scalar @test; $a++)
      {
      my $autocreate = 0;
      if($test[$a] eq 'fcopy')
        {
        $target = "FCOPY: ".$cfg->{'dest'}[$i];
        if(defined($cfg->{'createdest'}[$i]) && $cfg->{'createdest'}[$i] == 1)
          {
          $autocreate = 1;
          }
        }
      if($test[$a] eq 'ftp')
        {
        $target = "FTP: ".$cfg->{'ftp'}[$i]." (".$cfg->{'ftpdir'}[$i].")";
        if(defined($cfg->{'createftpdir'}[$i]) && $cfg->{'createftpdir'}[$i] == 1)
          {
          $autocreate = 1;
          }
        }
      if($test[$a] eq 'scp')
        {
        $target = "SCP: ".$cfg->{'scp'}[$i]." (".$cfg->{'scpopts'}[$i].")";
        }
      printf("Target destination %d.........: %s\n",$a,$target);
      if($autocreate)
        {
       printf("[%d] Auto-create target dest..: Yes\n",$a);
        }
      printf("[%d] Generations to hold......: %s\n",$a,$cfg->{'maxgen'}[$i]);
      printf("[%d] Defines pattern match....: ",$a);
      if($cfg->{'pattern'}[$i] == 1)
        {
        print("Yes\n");
        }
      else
        {
        print("No\n");
        }
      printf("[%d] Backup using named pipe..: ",$a);
      if($cfg->{'vldb'}[$i] == 1)
        {
        print("Yes\n");
        }
      else
        {
        print("No\n");
        }
      }
    print("\n");
    }
  }

###################################################################################################
#    NAME: ProcessBackup()
# PURPOSE: Processes on the backupped file according to settings for the passed setnr.
#   INPUT: $bfile => The backupfile to work on
#          $setnr => Corresponding backupset number
#  RETURN: 0 if all was okay else an positive value to indicate an error condition
###################################################################################################

sub ProcessBackup($$)
  {
  my ($bfile,$setnr) = @_;
  my @dummy;

  # V0.38: If given setnr is a pattern, skip it.
  if($cfg->{'pattern'}[$setnr] == 1)
    {
    return(0);
    }
  my $bfilesize = -s $bfile;
  @dummy = split(/,/,$cfg->{'mode'}[$setnr]);
  for(my $i = 0; $i < scalar @dummy; $i++)
    {
    if($dummy[$i] eq 'fcopy')
      {
      if(defined($cfg->{'createdest'}[$setnr]) && $cfg->{'createdest'}[$setnr] == 1)
        {
        my $rc = opendir(FH,$cfg->{'dest'}[$setnr]);
        if(!defined($rc))
          {
          eval
            {
            mkdir($cfg->{'dest'}[$setnr]) || die "ERROR: Unable to create destination directory!";
            };
          if($@)
            {
            AddError(sprintf("ProcessBackup(mkdir) FAILED!\nError while auto-creating destination directory: %s\n\n",$!));
            WriteToLog(sprintf("[%d] ERROR: MKDIR failed: %s (%s)",$setnr,$!,$cfg->{'name'}[$setnr]));
            unlink($bfile);
            return(1);
            }
          }
        else
          {
          closedir(FH);
          }
        }
      printf("Copying %s to %s (%s bytes)...",$bfile,$cfg->{'dest'}[$setnr],FormatNumber($bfilesize));
      WriteToLog(sprintf("[%d] Copying file \"%s\" to \"%s\" (%s bytes)",$setnr,basename($bfile),$cfg->{'dest'}[$setnr],FormatNumber($bfilesize)));
      my $sd = getmicrotime;
      my $rc = copy($bfile, $cfg->{'dest'}[$setnr]);
      if(!$rc)
        {
        AddError(sprintf("ProcessBackup(copy) FAILED!\nError while copying backupfile: %s\n\n",$!));
        WriteToLog(sprintf("[%d] ERROR: FCOPY failed: %s (%s)",$setnr,$!,$cfg->{'name'}[$setnr]));
        unlink($bfile);
        return(1);
        }
      my $ed = getmicrotime;
      my $kbspeed = ($bfilesize/(abs($ed-$sd)))/1024;
      printf("done (%.2f KB/sec)\n",$kbspeed);
      WriteToLog(sprintf("[%d] File \"%s\" successfully copied (%.2f KB/sec)",$setnr,$bfile,$kbspeed));
      next;
      }
    if($dummy[$i] eq 'ftp')
      {
      $cfg->{'ftp'}[$setnr]=~/(.*)(\:)(.*)(@)(.*)/;
      my $ftpuser = $1;
      my $ftppass = $3;
      my $ftphost = $5;
      printf("Sending file \"%s\" (%s bytes) to %s: ",$bfile,FormatNumber($bfilesize), $ftphost);
      WriteToLog(sprintf("[%d] Sending file \"%s\" via FTP to %s (%s bytes)",$setnr,basename($bfile),$ftphost,FormatNumber($bfilesize)));
      my $sd = getmicrotime;
      if(!UploadFTP($ftpuser,$ftppass,$ftphost,$bfile,$setnr))
        {
        unlink($bfile);
        return(2);
        }
      my $ed = getmicrotime;
      my $kbspeed = ($bfilesize/(abs($ed-$sd)))/1024;
      printf("done (%.2f KB/sec)\n",$kbspeed);
      WriteToLog(sprintf("[%d] File \"%s\" successfully send (%.2f KB/sec)",$setnr,$bfile,$kbspeed));
      next;
      }
    if($dummy[$i] eq 'scp')
      {
      $cfg->{'scp'}[$setnr]=~/(.*)(@)(.*)(\:)(.*)/;
      my $scpuser = (defined($1)) ? $1 : '';
      my $scphost = (defined($3)) ? $3 : '';
      my $scp_dir = (defined($5)) ? $5 : '';
      printf("Sending file \"%s\" (%s bytes) via SCP to %s@%s: ",$bfile,FormatNumber($bfilesize),$scpuser,$scphost);
      WriteToLog(sprintf("[%d] Sending file \"%s\" via SCP to %s@%s",$setnr,basename($bfile),$scpuser,$scphost));
      my $sd = getmicrotime;
      if(!UploadSCP($setnr,$bfile))
        {
        unlink($bfile);
        return(3);
        }
      my $ed = getmicrotime;
      my $kbspeed = ($bfilesize/(abs($ed-$sd)))/1024;
      printf("done (%.2f KB/sec)\n",$kbspeed);
      WriteToLog(sprintf("[%d] File \"%s\" successfully send (%.2f KB/sec)",$setnr,$bfile,$kbspeed));
      next;
      }
    }
  unlink($bfile);
  print("\n");
  WriteToLog(sprintf("[%d] Backup set #%d successfully processed.",$setnr,$setnr));
  return(0);
  }

###################################################################################################
#    NAME: UploadFTP()
# PURPOSE: Uploads $bfile to given FTP server
#   INPUT: $fuser => FTP Username
#          $fpass => FTP Password
#          $fhost => FTP Host (May include the port in format HOST:PORT)
#          $bfile => Backupfile to sent to
#          $setnr => Number of corresponding backupset
#  RETURN: In case of an error 0 is returned else 1
###################################################################################################

sub UploadFTP($$$$$)
  {
  my ($fuser,$fpass,$fhost,$bfile,$setnr) = @_;
  my $ftp;
  my @hostdata = split(/\:/,$fhost);

  # V0.38: If given setnr is a pattern, skip it.
  if($cfg->{'pattern'}[$setnr] == 1)
    {
    return(0);
    }
  if(!defined($hostdata[1]))
    {
    $hostdata[1] = '21';  # Default port is 21
    }
  eval
    {
    $ftp = Net::FTP->new($hostdata[0], Debug => 0, Port => $hostdata[1], Timeout => FTP_TIMEOUT) or die "$@";
    };
  if($@)
    {
    $@=~/(.*)(at.*)/i;
    AddError(sprintf("UploadFTP(connect) FAILED: Reason: %s\n\n",$1));
    WriteToLog(sprintf("[%d] ERROR: UploadFTP(#%d) FAILED: %s",$setnr,$setnr,$1));
    return(0);
    }
  if(!$ftp->login($fuser,$fpass))
    {
    my $errmsg = (defined($ftp->message)) ? $ftp->message : '-N/A-';
    AddError(sprintf("UploadFTP(login) FAILED!\nFTP-Server says: %s\n",$errmsg));
    WriteToLog(sprintf("[%d] ERROR: UploadFTP(#%d) LOGIN FAILED: %s",$setnr,$setnr,$errmsg));
    $ftp->quit;
    return(0);
    }
  if($cfg->{'ftpdir'}[$setnr] ne '')
    {
    if(!$ftp->cwd($cfg->{'ftpdir'}[$setnr]))
      {
      if(!defined($cfg->{'createftpdir'}) || $cfg->{'createftpdir'} == 0)
        {
        AddError(sprintf("UploadFTP(cwd) failed!\nFTP-Server says: %s\n",$ftp->message));
        WriteToLog(sprintf("[%d] ERROR: UploadFTP(#%d) CWD FAILED: %s",$setnr,$setnr,$ftp->message));
        $ftp->quit;
        return(0);
        }
      else
        {
        eval
          {
          $ftp->mkdir($cfg->{'ftpdir'}[$setnr]) || die "FTP-MKDIR failure";
          };
        if($@)
          {
          AddError(sprintf("UploadFTP(mkdir) failed!\nFTP-Server says: %s\n",$ftp->message));
          WriteToLog(sprintf("[%d] ERROR: UploadFTP(#%d) MKDIR FAILED: %s",$setnr,$setnr,$ftp->message));
          $ftp->quit;
          return(0);
          }
        if(!$ftp->cwd($cfg->{'ftpdir'}[$setnr]))
          {
          AddError(sprintf("UploadFTP(cwd) failed!\nFTP-Server says: %s\n",$ftp->message));
          WriteToLog(sprintf("[%d] ERROR: UploadFTP(#%d) CWD FAILED: %s",$setnr,$setnr,$ftp->message));
          $ftp->quit;
          return(0);
          }
        }
      }
    }
  $ftp->binary;
  $ftp->put($bfile,basename($bfile));
  $ftp->quit;
  return(1);
  }

###################################################################################################
#    NAME: UploadSCP()
# PURPOSE: Uploads $bfile to given SCP server
#   INPUT: $bfile => Backupfile to sent to
#          $setnr => Number of corresponding backupset
#  RETURN: In case of an error 0 is returned else 1
###################################################################################################

sub UploadSCP($$)
  {
  my ($setnr,$bfile) = @_;

  # V0.38: If given setnr is a pattern, skip it.
  if($cfg->{'pattern'}[$setnr] == 1)
    {
    return(0);
    }
  # Build commandline:
  my $cmd = sprintf("%s %s %s %s",$cfg->{'scp_bin'},$cfg->{'scpopts'}[$setnr],$bfile,$cfg->{'scp'}[$setnr]);
  if(ExecuteCMD($cmd,sprintf("UploadSCP(%d)->scp",$setnr),$cfg->{'scp_bin'}))
    {
    return(0);
    }
  return(1);
  }

###################################################################################################
#    NAME: TarAndZipSet()
# PURPOSE: Creates the tar.gz or tar.bz2 file for passed set number
#   INPUT: Backup set number to work on
#  RETURN: Full pathname of created backupfile
#   NOTES: V0.2: Checks first if directory definition contains oracle export, in this
#                case we branch to the corresponding function and return the result of it.
###################################################################################################

sub TarAndZipSet($)
  {
  my ($setnr) = @_;
  my $targetname;

  # V0.38: If given setnr is a pattern, skip it.
  if($cfg->{'pattern'}[$setnr] == 1)
    {
    return(0);
    }
  printf("Processing set #%d (%s)...",$setnr,$cfg->{'name'}[$setnr]);
  my $data = $cfg->{'dir'}[$setnr];
  if($data=~/^ORACLE\:/)
    {
    return(ExportOracle($setnr));
    }
  elsif($data=~/^MYSQL\:/ || $data=~/^MYSQL56\+\:/)
    {
    return(ExportMySQL($setnr));
    }
  my $st = getmicrotime;
  if(!-d $cfg->{'dir'}[$setnr] || !-R $cfg->{'dir'}[$setnr])
    {
    AddError(sprintf("TarAndZipSet(%d) FAILED!\n'%s': %s!\n\n",$setnr,$cfg->{'dir'}[$setnr],$!));
    WriteToLog(sprintf("[%d] ERROR: '%s': %s!",$setnr,$cfg->{'dir'}[$setnr],$!));
    return(undef);
    }
  if(!-d $cfg->{'tmpdir'} || !-w $cfg->{'tmpdir'})
    {
    AddError(sprintf("TarAndZipSet(%d) FAILED!\nTempdir '%s' does not exist or is not writeable!\n\n",$setnr,$cfg->{'tmpdir'}));
    WriteToLog(sprintf("[%d] TarAndZipSet(%d): Tempdir '%s' does not exist or is not writeable!",$setnr,$setnr,$cfg->{'tmpdir'}));
    return(undef);
    }
  # TAR the file:
  print(".");
  my @tiarray = localtime (time());
  my $myyear = $tiarray[5];
  if($myyear > 70)
	  {
	  $myyear+= 1900;
	  }
  else
	  {
	  $myyear+= 2000;
	  }
  $targetname = sprintf("%s/%s_%4d%02d%02d_%02d%02d%02d",$cfg->{'tmpdir'},$cfg->{'name'}[$setnr],$myyear,($tiarray[4]+1),$tiarray[3],$tiarray[2],$tiarray[1],$tiarray[0]);
  WriteToLog(sprintf("[%d] Creating file \"%s.tar%s\" from set #%d (%s)",$setnr,basename($targetname),$cfg->{'ext'},$setnr,$cfg->{'name'}[$setnr]));
  my $cmd = sprintf("%s %s %s.tar%s %s >/dev/null 2>>tar_stderr.log",$cfg->{'tar'},$cfg->{'taropts'},$targetname,$cfg->{'ext'},$cfg->{'dir'}[$setnr]);
  if(ExecuteCMD($cmd,sprintf("TarAndZipSet(%d)->tar",$setnr),$cfg->{'tar'}))
    {
    unlink($targetname.'.tar'.$cfg->{'ext'});
    return(undef);
    }
  my $et = getmicrotime;
  my $tsize = -s $targetname.'.tar'.$cfg->{'ext'};
  printf("done, file is %s bytes (%2.3fs).\n",FormatNumber($tsize),abs($et-$st));
  WriteToLog(sprintf("[%d] Backup file \"%s.tar%s\" successfully created (%s bytes, took %2.3fs).",$setnr,basename($targetname),$cfg->{'ext'},FormatNumber($tsize),abs($et-$st)));
  return($targetname.'.tar'.$cfg->{'ext'});
  }

###################################################################################################
#    NAME: ExportOracle()
# PURPOSE: Exports an Oracle Database with the help of exp
#   INPUT: SetNr -> Backupset to work on
#  RETURN: Full backupfile name with extension or undef in case of an error
###################################################################################################

sub ExportOracle($)
  {
  my ($setnr) = @_;

  my $st = getmicrotime;
  my $schema = "";
  my $orahost = "";
  my $data = $cfg->{'dir'}[$setnr];

  if(!defined($ENV{'ORACLE_HOME'}))
    {
    AddError(sprint("ExportOracle() FAILED!\n\nERROR: ORACLE_HOME environment variable not found, Oracle Support disabled!\n\n"));
    WriteToLog(sprintf("[%d] ERROR: ORACLE_HOME env var not found (%s)",$setnr,$cfg->{'name'}[$setnr]));
    return(undef);
    }
  my @dummy = split /\|/,$data;
  if(defined($dummy[1]) && $dummy[1] ne '')
    {
    $schema = $dummy[1];
    }
  my $oralogin = $dummy[0];
  $oralogin=~s/^ORACLE://;
  my @dummy2 = split /\@/,$oralogin;
  if(defined($dummy2[1]) && $dummy2[1] ne '')
    {
    $orahost = "database ".$dummy2[1];
    }
  else
    {
    $orahost = "local database (".(defined($ENV{'ORACLE_SID'}) ? $ENV{'ORACLE_SID'} : 'No ORACLE_SID set ?!').")";
    }
  my $oraexport = sprintf("%s/bin/exp",$ENV{'ORACLE_HOME'});
  if(!-x $oraexport)
    {
    AddError(sprintf("ExportOracle() FAILED!\n\nERROR: Oracle Export not found / not executable!\n\n"));
    WriteToLog(sprintf("[%d] ERROR: Oracle Export not found / not executable! (%s)",$setnr,$cfg->{'name'}[$setnr]));
    return(undef);
    }
  if($cfg->{'vldb'}[$setnr])
    {
    return(ExportOracleVLDB($setnr,$oralogin,$schema,$orahost,$oraexport));
    }
  my $cmdline;
  my $targetname = "";
  my $targetlog  = "";
  print(".");
  my @tiarray = localtime (time());
  my $myyear = $tiarray[5];
  if($myyear > 70)
	  {
	  $myyear+= 1900;
	  }
  else
	  {
	  $myyear+= 2000;
	  }
  $targetname = sprintf("%s/%s_%4d%02d%02d_%02d%02d%02d.dmp",$cfg->{'tmpdir'},$cfg->{'name'}[$setnr],$myyear,($tiarray[4]+1),$tiarray[3],$tiarray[2],$tiarray[1],$tiarray[0]);
  $targetlog  = sprintf("%s/%s_%4d%02d%02d_%02d%02d%02d.log",$cfg->{'tmpdir'},$cfg->{'name'}[$setnr],$myyear,($tiarray[4]+1),$tiarray[3],$tiarray[2],$tiarray[1],$tiarray[0]);
  if($schema eq '')
    {
    WriteToLog(sprintf("[%d] Starting Oracle Export of whole %s",$setnr,$orahost));
    $cmdline = sprintf("%s USERID=%s FILE=%s LOG=%s FULL=Y ROWS=Y INDEXES=Y CONSISTENT=Y STATISTICS=NONE >/dev/null 2>&1",$oraexport,$oralogin,$targetname,$targetlog);
    }
  else
    {
    WriteToLog(sprintf("[%d] Starting Oracle Export of schema %s from %s",$setnr,$schema,$orahost));
    $cmdline = sprintf("%s USERID=%s FILE=%s LOG=%s OWNER=%s ROWS=Y INDEXES=Y CONSISTENT=Y STATISTICS=NONE >/dev/null 2>&1",$oraexport,$oralogin,$targetname,$targetlog,$schema);
    }
  if(ExecuteCMD($cmdline,sprintf("ExportOracle(%d)->exp",$setnr),"exp"))
    {
    unlink($targetname);
    unlink($targetlog);
    return(undef);
    }

  # And TAR the files:

  print(".");
  my $tarname = sprintf("%s/%s_%4d%02d%02d_%02d%02d%02d",$cfg->{'tmpdir'},$cfg->{'name'}[$setnr],$myyear,($tiarray[4]+1),$tiarray[3],$tiarray[2],$tiarray[1],$tiarray[0]);
  my $cmd     = sprintf("%s %s %s.tar%s %s %s >/dev/null 2>&1",$cfg->{'tar'},$cfg->{'taropts'},$tarname,$cfg->{'ext'},$targetname,$targetlog);

  if(ExecuteCMD($cmd,sprintf("ExportOracle(%d)->tar",$setnr),$cfg->{'tar'}))
    {
    unlink($targetname);
    unlink($targetlog);
    return(undef);
    }
  unlink($targetname);
  unlink($targetlog);
  my $et = getmicrotime;
  printf("done (%2.3fs).\n",abs($et-$st));
  WriteToLog(sprintf("[%d] Oracle Export finished after %2.3fs",$setnr,abs($et-$st)));
  return($tarname.'.tar'.$cfg->{'ext'});
  }

###################################################################################################
#    NAME: ExportOracleVLDB()
# PURPOSE: Exports an Oracle Database with the help of exp via a named pipe
#   INPUT: SetNr    -> Backupset to work on
#          Oralogin -> User/password@TNS
#          OraHost  -> Schema
#  RETURN: Full backupfile name with extension or undef in case of an error
###################################################################################################

sub ExportOracleVLDB($$$$$)
  {
  my ($setnr,$ologin,$schema,$orahost,$oraexport) = @_;
  my $st = getmicrotime;

  # Make sure that we have ONLY (!) FCOPY mode active for this backupset, FTP via named pipe would be useless:

  my @dummy = split(/,/,$cfg->{'mode'}[$setnr]);
  for(my $i = 0; $i < scalar @dummy; $i++)
    {
    if($dummy[$i] ne 'fcopy')
      {
      AddError(sprintf("Only FCOPY mode is allowed for VLDB backup mode (Set #%d) - Skipping entry!",$setnr));
      WriteToLog(sprintf("[%d] ERROR: Only FCOPY mode is allowed for VLDB backup mode (Set #%d) - Skipping entry!",$setnr,$setnr));
      }
    }
  # First we create the named pipe based on the name of the backupset:
  my $pipename = sprintf("exportpipe_%s.%d",$cfg->{'name'}[$setnr],$setnr);
  my $cmd = sprintf("%s %s p",$cfg->{'mknod'},$pipename);
  if(ExecuteCMD($cmd,sprintf("ExportOracleVLDB(%d)->mknod",$setnr),"mknod"))
    {
    return(undef);
    }

  # Now we have to start the packer in background, as the pipe is FIFO, therefor first the writer process:

  my $targetname = "";
  my $targetlog  = "";
  print(".");
  my @tiarray = localtime (time());
  my $myyear = $tiarray[5];
  if($myyear > 70)
	  {
	  $myyear+= 1900;
	  }
  else
	  {
	  $myyear+= 2000;
	  }
  $targetname = sprintf("%s/%s_%4d%02d%02d_%02d%02d%02d.dmp%s",$cfg->{'dest'}[$setnr],$cfg->{'name'}[$setnr],$myyear,($tiarray[4]+1),$tiarray[3],$tiarray[2],$tiarray[1],$tiarray[0],$cfg->{'ext'});
  $cmd = sprintf("%s --stdout < %s > %s &",$cfg->{'gzip'},$pipename,$targetname);
  if(ExecuteCMD($cmd,sprintf("ExportOracleVLDB(%d)->gzip_bg",$setnr),"gzip"))
    {
    unlink $pipename;
    return(undef);
    }

  # Packer is now started, next we must start export and pointing the dump file to our pipe:

  if($schema eq '')
    {
    WriteToLog(sprintf("[%d] Starting Oracle Export of whole %s",$setnr,$orahost));
    $cmd = sprintf("%s USERID=%s FILE=%s FULL=Y ROWS=Y INDEXES=Y CONSISTENT=Y STATISTICS=NONE >/dev/null 2>&1",$oraexport,$ologin,$pipename);
    }
  else
    {
    WriteToLog(sprintf("[%d] Starting Oracle Export of schema %s from %s",$setnr,$schema,$orahost));
    $cmd = sprintf("%s USERID=%s FILE=%s OWNER=%s ROWS=Y INDEXES=Y CONSISTENT=Y STATISTICS=NONE >/dev/null 2>&1",$oraexport,$ologin,$pipename,$schema);
    }
  system($cmd);
  if(ExecuteCMD($cmd,sprintf("ExportOracleVLDB(%d)->exp",$setnr),"exp"))
    {
    unlink($targetname);
    unlink($pipename);
    return(undef);
    }

  # Finally we have to remove the named pipe:
  unlink $pipename;
  my $et = getmicrotime;
  printf("done (%2.3fs).\n",abs($et-$st));
  # As this is a special behavour here, we call CheckGenerations() directly from here and return
  # a NULL name to our callee functions, avoiding any further action on that backupset.
  CheckGenerations($setnr,CALL_BAK);
  return(undef);
  }

###################################################################################################
#    NAME: ExportMySQL()
# PURPOSE: Exports an MySQL Database with the help of mysqldump
#   INPUT: SetNr -> Backupset to work on
#  RETURN: Full backupfile name with extension or undef in case of an error
#   NOTES: Format of connect string is <username>/<password>@<hostname>|<database>
###################################################################################################

sub ExportMySQL($)
  {
  my ($setnr)   = @_;
  my $st        = getmicrotime;
  my $mysqluser = $cfg->{'muser'}[$setnr];
  my $mysqlpass = $cfg->{'mpass'}[$setnr];
  my $mysqldb   = $cfg->{'mdb'}[$setnr];
  my $mysqlhost = $cfg->{'mhost'}[$setnr];
  my $data      = $cfg->{'dir'}[$setnr];
  my $mysqllocal= $cfg->{'mlocal'}[$setnr];
  my $cmdline;
  my $targetname= "";
  my $pwsection = "";

  print(".");
  my @tiarray = localtime (time());
  my $myyear = $tiarray[5];
  if($myyear > 70)
	  {
	  $myyear+= 1900;
	  }
  else
	  {
	  $myyear+= 2000;
	  }
  if(defined($mysqlpass) && $mysqlpass ne "")
    {
    $pwsection = sprintf("--password=%s",$mysqlpass);
    }
  $targetname = sprintf("%s/%s_%4d%02d%02d_%02d%02d%02d.sql%s",$cfg->{'tmpdir'},$cfg->{'name'}[$setnr],$myyear,($tiarray[4]+1),$tiarray[3],$tiarray[2],$tiarray[1],$tiarray[0],$cfg->{'ext'});
  if($mysqldb eq '')
    {
    if($mysqllocal ne "")
      {
      WriteToLog(sprintf("[%d] Starting MySQL Export of whole database from loginpath %s",$setnr,$mysqllocal));
      $cmdline = sprintf("%s --login-path=%s --user=%s --all-databases %s | %s >%s",$cfg->{'mysqldump'},$mysqllocal,$mysqluser,$cfg->{'mysqldumpopts'},$cfg->{'gzip'},$targetname);
      }
    else
      {
      WriteToLog(sprintf("[%d] Starting MySQL Export of whole database from host %s",$setnr,$mysqlhost));
      $cmdline = sprintf("%s --user=%s %s --host=%s --all-databases %s | %s >%s",$cfg->{'mysqldump'},$mysqluser,$pwsection,$mysqlhost,$cfg->{'mysqldumpopts'},$cfg->{'gzip'},$targetname);
      }
    }
  else
    {
    if($mysqllocal ne "")
      {
      WriteToLog(sprintf("[%d] Starting MySQL Export of database %s from loginpath %s",$setnr,$mysqldb,$mysqllocal));
      $cmdline = sprintf("%s --login-path=%s --user=%s %s %s | %s >%s",$cfg->{'mysqldump'},$mysqllocal,$mysqluser,$cfg->{'mysqldumpopts'},$mysqldb,$cfg->{'gzip'},$targetname);
      }
    else
      {
      WriteToLog(sprintf("[%d] Starting MySQL Export of database %s from host %s",$setnr,$mysqldb,$mysqlhost));
      $cmdline = sprintf("%s --user=%s %s --host=%s %s %s | %s >%s",$cfg->{'mysqldump'},$mysqluser,$pwsection,$mysqlhost,$cfg->{'mysqldumpopts'},$mysqldb,$cfg->{'gzip'},$targetname);
      }
    }
  #printf("CMD=|%s|\n",$cmdline);
  if(ExecuteCMD($cmdline,sprintf("ExportMySQL(%d)->mysqldump",$setnr),"mysqldump"))
    {
    unlink($targetname);
    return(undef);
    }
  my $et = getmicrotime;
  printf("done (%2.3fs).\n",abs($et-$st));
  WriteToLog(sprintf("[%d] MySQL Export finished after %2.3fs",$setnr,abs($et-$st)));
  return($targetname);
  }

###################################################################################################
#    NAME: CheckGenerations()
# PURPOSE: Performs check on available generations for a given backupset. If more generations
#          available than configured this routine removes the oldest entries.
#   INPUT: $setnr     => Backupset number to work on
#          $calltype  => How we are called: 0 = Commandline (interactive) | 1 = internal
#  RETURN: None
###################################################################################################

sub CheckGenerations($$)
  {
  my ($setnr,$calltype) = @_;
  my $target      = '';
  my $tname       = '';
  my $filecount   = 0;
  my $currentmode = 0;
  my @availfiles;
  my $removedfiles= 0;
  my @ftpkillfiles;       # We copy here all ftp files to remove and remove them at once (if any)
  my @scpkillfiles;       # Same here for SCP

  if(!defined($cfg->{'maxgen'}[$setnr]) || int($cfg->{'maxgen'}[$setnr])==0)    # We only check if MAXGEN is configured AND > 0
    {
    return;
    }
  # V0.38: If given setnr is a pattern, skip it.
  if($cfg->{'pattern'}[$setnr] == 1)
    {
    return;
    }
  if(!$calltype)
    {
    PrintLog(sprintf("[%d] CheckGenerations: Backup Set #%d (%s) has max. files to keep set to \"%d\".\n",$setnr,$setnr,$cfg->{'name'}[$setnr],$cfg->{'maxgen'}[$setnr]));
    }
  my @test = split(/,/,$cfg->{'mode'}[$setnr]);
  for(my $a =0; $a < scalar @test; $a++)
    {
    if($test[$a] eq 'fcopy')
      {
      $target = "FCOPY (".$cfg->{'dest'}[$setnr].")";
      $tname  = "FCOPY";
      @availfiles = ReadFileCopies($setnr, $cfg->{'dest'}[$setnr]);
      $currentmode = MODE_FCOPY;
      }
    elsif($test[$a] eq 'ftp')
      {
      my @dummy = split(/\@/,$cfg->{'ftp'}[$setnr]);
      $target = "FTP (".$dummy[1].")";
      $tname  = "FTP";
      @availfiles = ReadFTPCopies($setnr);
      $currentmode = MODE_FTP;
      }
    elsif($test[$a] eq 'scp')
      {
      $target = "SCP (".$cfg->{'scp'}[$setnr].")";
      $tname  = "SCP";
      @availfiles = ReadSCPCopies($setnr);
      $currentmode = MODE_SCP;
      }
    else
      {
      die("Unknown mode ".$test[$a]." detected!!!!");
      }
    # V0.38: In case of a problem we return here instead of trying to work on a null array...
    if(!defined($availfiles[0]) || scalar @availfiles == 0)
      {
      return;
      }
    @availfiles = sort(@availfiles);
    $filecount  = scalar @availfiles;
    if(!$calltype)
      {
      PrintLog(sprintf("[%d] CheckGenerations: Target \"%s\" has %d files.\n",$setnr,$tname,scalar @availfiles));
      }
    if($filecount > $cfg->{'maxgen'}[$setnr])
      {
      for(my $r = 0; $r < $filecount - $cfg->{'maxgen'}[$setnr]; $r++)
        {
        if($currentmode == MODE_FCOPY)
          {
          my $delname = sprintf("%s/%s",$cfg->{'dest'}[$setnr],$availfiles[$r]);
          if(!$calltype)
            {
            printf("Removing file \"%s\"\n",$delname);
            }
          WriteToLog(sprintf("[%d] Removing FCOPY file \"%s\" [MAX: %d | NOW: %d]",$setnr,basename($delname),$cfg->{'maxgen'}[$setnr],($filecount-$r)));
          unlink $delname;
          $removedfiles++;
          }
        elsif($currentmode == MODE_FTP)
          {
          push @ftpkillfiles, $availfiles[$r];
          }
        elsif($currentmode == MODE_SCP)
          {
          push @scpkillfiles, $availfiles[$r];
          }
        }
      if(@ftpkillfiles)
        {
        $removedfiles+=RemoveFTPFiles($setnr,$filecount,@ftpkillfiles);
        undef @ftpkillfiles;
        }
      if(@scpkillfiles)
        {
        $removedfiles+=RemoveSCPFiles($setnr,$filecount,@scpkillfiles);
        undef @scpkillfiles;
        }
      } # End filecount > ..
    }
  if($removedfiles)
    {
    PrintLog(sprintf("[%d] Check Generations: Removed %s backupfile(s) from Backup set #%d.\n\n",$setnr,FormatNumber($removedfiles),$setnr));
    }
  }

###################################################################################################
#    NAME: RemoveFTPFiles()
# PURPOSE: Removes a list of files from $setnr ftp host
#   INPUT: $setnr   => Backupset number to work on
#          @rmfiles => Array of files to remove from given $setnr FTPHOST.
#  RETURN: Amount of files removed
###################################################################################################

sub RemoveFTPFiles($$@)
  {
  my ($setnr, $filecount,@rmfiles) = @_;
  my $rfiles  = 0;
  my $ftp;

  $cfg->{'ftp'}[$setnr]=~/(.*)(\:)(.*)(@)(.*)/;
  my $ftpuser = $1;
  my $ftppass = $3;
  my $ftphost = $5;
  my @hostdata = split(/\:/,$ftphost);

  # V0.38: If given setnr is a pattern, skip it.
  if($cfg->{'pattern'}[$setnr] == 1)
    {
    return(0);
    }
  if(!defined($hostdata[1]))
    {
    $hostdata[1] = '21';  # Default port is 21
    }
  eval
    {
    $ftp = Net::FTP->new($hostdata[0], Debug => 0, Port => $hostdata[1], Timeout => FTP_TIMEOUT) or die "$@";
    };
  if($@)
    {
    $@=~/(.*)(at.*)/i;
    AddError(sprintf("RemoveFTPFiles(connect) FAILED: Reason: %s\n\n",$1));
    WriteToLog(sprintf("[%d] ERROR: RemoveFTPFiles(#%d) FAILED: %s",$setnr,$setnr,$1));
    return(undef);
    }
  if(!$ftp->login($ftpuser,$ftppass))
    {
    AddError(sprintf("RemoveFTPFiles(login) FAILED!\nFTP-Server says: %s\n",$ftp->message));
    WriteToLog(sprintf("[%d] ERROR: RemoveFTPFiles(#%d) LOGIN FAILED: %s",$setnr,$setnr,$ftp->message));
    $ftp->quit;
    return(undef);
    }
  if($cfg->{'ftpdir'}[$setnr] ne '')
    {
    if(!$ftp->cwd($cfg->{'ftpdir'}[$setnr]))
      {
      AddError(sprintf("RemoveFTPFiles(cwd) failed!\nFTP-Server says: %s\n",$ftp->message));
      WriteToLog(sprintf("[%d] ERROR: RemoveFTPFiles(#%d) CWD FAILED: %s",$setnr,$setnr,$ftp->message));
      $ftp->quit;
      return(undef);
      }
    }
  for(my $i = 0; $i < scalar @rmfiles; $i++)
    {
    eval
      {
      $ftp->delete($rmfiles[$i]);
      WriteToLog(sprintf("[%d] Removing FTP file \"%s\" [MAX: %d | NOW: %d]",$setnr,$rmfiles[$i],$cfg->{'maxgen'}[$setnr],($filecount - $i)));
      $rfiles++;
      };
    if($@)  # In case of an error we inform the user but continue.
      {
      AddError(sprintf("RemoveFTPFiles(delete) failed!\nFTP-Server says: %s\n",$ftp->message));
      WriteToLog(sprintf("[%d] ERROR: RemoveFTPFiles(%d)->delete(%s) failed: %s\n",$setnr,$setnr,$rmfiles[$i],$ftp->message));
      }
    }
  $ftp->quit;
  return($rfiles);
  }

###################################################################################################
#    NAME: ReadFileCopies()
# PURPOSE: Reads available backups from filesystem and returns array of found backup filenames
#   INPUT: $setnr   => Backupset number to work on
#          $target  => Parsed target directory where to find the files.
#  RETURN: Array of found backups or undef in case of an error
###################################################################################################

sub ReadFileCopies($$)
  {
  my ($setnr, $targetdir) = @_;
  my @backupfiles;
  my @entries;
  my $namematch = $cfg->{'name'}[$setnr].'_\d{8}_\d{6}';    # RegEx to find the backupfiles

  # V0.38: If given setnr is a pattern, skip it.
  if($cfg->{'pattern'}[$setnr] == 1)
    {
    return(0);
    }
  opendir THISDIR, $targetdir || die "cannot open $targetdir for reading\n";
  my @files = readdir THISDIR;
  close THISDIR;
  @entries = grep !/^\.\.?$/,@files;
  @entries = sort @entries;
  for(my $i = 0; $i < scalar @entries; $i++)
    {
    if($entries[$i]=~/^$namematch/)
      {
      push @backupfiles, $entries[$i];
      }
    }
  return(@backupfiles);
  }

###################################################################################################
#    NAME: ReadFTPCopies()
# PURPOSE: Reads available backups from FTP server and returns array of found backup filenames
#   INPUT: $setnr   => Backupset number to work on
#  RETURN: Array of found backups or undef in case of an error
###################################################################################################

sub ReadFTPCopies($)
  {
  my ($setnr) = @_;
  my $namematch = $cfg->{'name'}[$setnr].'_\d{8}_\d{6}';    # RegEx to find the backupfiles
  my @entries;
  my @backupfiles;
  my $ftp;

  # V0.38: If given setnr is a pattern, skip it.
  if($cfg->{'pattern'}[$setnr] == 1)
    {
    return(undef);
    }
  $cfg->{'ftp'}[$setnr]=~/(.*)(\:)(.*)(@)(.*)/;
  my $ftpuser = $1;
  my $ftppass = $3;
  my $ftphost = $5;
  my @hostdata = split(/\:/,$ftphost);
  if(!defined($hostdata[1]))
    {
    $hostdata[1] = '21';  # Default port is 21
    }
  eval
    {
    $ftp = Net::FTP->new($hostdata[0], Debug => 0, Port => $hostdata[1], Timeout => FTP_TIMEOUT) or die "$@";
    };
  if($@)
    {
    $@=~/(.*)(at.*)/i;
    AddError(sprintf("ReadFTPCopies(connect) FAILED: Reason: %s\n\n",$1));
    WriteToLog(sprintf("ERROR: ReadFTPCopies(#%d) FAILED: %s",$setnr,$1));
    return(undef);
    }
  if(!$ftp->login($ftpuser,$ftppass))
    {
    AddError(sprintf("ReadFTPCopies(login) FAILED!\nFTP-Server says: %s\n",$ftp->message));
    WriteToLog(sprintf("ERROR: ReadFTPCopies(#%d) LOGIN FAILED: %s",$setnr,$ftp->message));
    $ftp->quit;
    return(undef);
    }
  if($cfg->{'ftpdir'}[$setnr] ne '')
    {
    if(!$ftp->cwd($cfg->{'ftpdir'}[$setnr]))
      {
      AddError(sprintf("ReadFTPCopies(cwd) failed!\nFTP-Server says: %s\n",$ftp->message));
      WriteToLog(sprintf("ERROR: ReadFTPCopies(#%d) CWD FAILED: %s",$setnr,$ftp->message));
      $ftp->quit;
      return(undef);
      }
    }
  @entries = $ftp->ls;
  $ftp->quit;
  # Now filter out the data for the current backupset name:
  for(my $i = 0; $i < scalar @entries; $i++)
    {
    if($entries[$i]=~/^$namematch/)
      {
      push @backupfiles, $entries[$i];
      }
    }
  return(@backupfiles);
  }

###################################################################################################
#    NAME: ReadSCPCopies()
# PURPOSE: Reads available backups from SCP server and returns array of found backup filenames
#   INPUT: $setnr => Backupset number to work on
#  RETURN: Array of found backups or undef in case of an error
###################################################################################################

sub ReadSCPCopies($)
  {
  my ($setnr) = @_;
  my $namematch = $cfg->{'name'}[$setnr].'_\d{8}_\d{6}';    # RegEx to find the backupfiles
  my @backupfiles;
  my $linebuf = '';

  # V0.38: If given setnr is a pattern, skip it.
  if($cfg->{'pattern'}[$setnr] == 1)
    {
    return(undef);
    }
  $cfg->{'scp'}[$setnr]=~/(.*)(@)(.*)(\:)(.*)/;
  my $scpuser = (defined($1)) ? $1 : '';
  my $scphost = (defined($3)) ? $3 : '';
  my $scp_dir = (defined($5)) ? $5 : '';
  my ($fh, $tmpfile) = tempfile();
  my $cmd = sprintf("%s %s %s@%s \"ls -1 %s\" >%s",$cfg->{'ssh_bin'},$cfg->{'sshopts'}[$setnr],$scpuser,$scphost,$scp_dir,$tmpfile);
  if(ExecuteCMD($cmd,sprintf("ReadSCPCopies(%d)->ssh",$setnr),$cfg->{'ssh_bin'}))
    {
    close($fh);
    unlink($tmpfile);
    return(undef);
    }
  seek($fh,0,0);
  while(<$fh>)
    {
    if($_=~/$namematch/)
      {
      $linebuf = $_;
      chomp($linebuf);
      push @backupfiles, $linebuf;
      }
    }
  close($fh);
  unlink($tmpfile);
  return(@backupfiles);
  }

###################################################################################################
#    NAME: RemoveSCPFiles()
# PURPOSE: Removes a list of files from $setnr SCP host
#   INPUT: $setnr   => Backupset number to work on
#          @rmfiles => Array of files to remove.
#  RETURN: Amount of files removed
###################################################################################################

sub RemoveSCPFiles($$@)
  {
  my ($setnr, $filecount, @rmfiles) = @_;
  my $rfiles  = 0;
  my $rm_cmd  = '';

  $cfg->{'scp'}[$setnr]=~/(.*)(@)(.*)(\:)(.*)/;
  my $scpuser = (defined($1)) ? $1 : '';
  my $scphost = (defined($3)) ? $3 : '';
  my $scp_dir = (defined($5)) ? $5 : '';

  for(my $i = 0; $i < scalar @rmfiles; $i++)
    {
    WriteToLog(sprintf("[%d] Removing SCP file \"%s\" [MAX: %d | Now: %d]",$setnr,$rmfiles[$i],$cfg->{'maxgen'}[$setnr],($filecount - $i)));
    $rm_cmd = sprintf("%s %s %s@%s \"rm -f %s/%s\"",$cfg->{'ssh_bin'},$cfg->{'sshopts'}[$setnr],$scpuser,$scphost,$scp_dir,$rmfiles[$i]);
    if(!(ExecuteCMD($rm_cmd,sprintf("Removing SCP file %s",$rmfiles[$i]),$cfg->{'ssh_bin'})))
      {
      $rfiles++;
      }
    }
  return($rfiles);
  }

__END__

=head1 NAME

SGLBackup.pl - Configurable backupper for various projects and/or Databases.

=head1 SYNOPSIS

SGLBackup.pl [options]

 Options:
   --help       Brief help message
   --man        full documentation
   --config     Alternative configfile (default is config.ini)
   --backupset  Number of backupset to process (default is all)
   --showconfig Lists parsed configuration and exit
   --checkgen   Performs checks on available generations

=head1 OPTIONS

=over 14

=item B<--help>

Print a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=item B<--config>

Specify an alternative configuration file.
If you ommit this parameter the default of
B<config.ini> is used.

=item B<--backupset>

Pass here the backupset number you wish to process.
If this parameter is not set all backupsets are processed.

=item B<--showconfig>

Dumps out the parsed configuration and exits.

=item B<--checkgen>

Checks amount of available backup files on destination and
clean up oldest files if more than configured files are found.
This process is also performed after every backup, here you can
call it manually if you wish. Note that only these backup files
are checked which have the MAXGEN_<x> parameter set, all other
are skipped.

=back

=head1 DESCRIPTION

This script will take a number of directories, tars one by one
and compress it with your favourite packer. Finally the packed
files can be sent via FTP, copied to an backup device etc.
Additional to normal filesystem backups one can backup also
Oracle and MySQL Databases with this script. To have Database
support you need "mysqldump" for MySQL and a full installation
of Oracle (either server or client) to have Oracle support enabled.
Please see supplied README file for more details.

=head1 AUTHOR

Written 2003-2015 by Sascha 'SieGeL' Pfalz <webmaster@saschapfalz.de>

Released under the GNU public licence.

=head1 VERSION

This is SGLBackup.pl B<V0.51>

For changes see file CHANGELOG.

=cut
