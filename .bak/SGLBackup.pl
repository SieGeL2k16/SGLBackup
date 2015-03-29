#!/usr/local/bin/perl -w
#
# This Script takes directories out of a config file
# tars them and copies the tared and zipped files over
# various locations configurable via an external config file.
# $Id: SGLBackup.pl,v 1.5 2005/02/04 23:29:39 siegel Exp $
###############################################################################
use strict;                       # Enforce all warnings
use Config::IniFiles;             # Used to parse the config file
use Getopt::Long;                 # Used for command-line parsing
use Pod::Usage;                   # Used for command-line help
use Time::HiRes qw(gettimeofday); # For measurements (transfer speeds etc.) 
use Net::FTP;                     # FTP Backup support
use File::Copy;                   # Filecopy/Move functions
use File::Basename;               # Filename manipulation

###############################################################################
# Prototypes
###############################################################################

sub main();                       # Main entry of this script
sub ReadConfig($);                # Sub to read and parse the configfile
sub getmicrotime;                 # Measures speed
sub TarAndZipSet($);              # Creates the backup file
sub ProcessBackup($$);            # Either filecopy or FTP the backup file and removes it from temp  
sub UploadFTP($$$$$);             # Upload to a given FTP server
sub ExportOracle($);              # Allows to export an oracle schema

###############################################################################
# Global Variables
###############################################################################

use constant VER => '0.2';        # Version of this script
my %bd;                           # Backup Dirs, stored as DIR_0/NAME_0 pairs
my $cfgfile = 'config.ini';       # Config filename, can be changed via --config=<> parameter      
my $cfg;                          # Configuration settings stored as hash ref
my $bsets   = '-1';               # Which backupset to process. (-1 process all)

###############################################################################
# Start of script           
###############################################################################

my $mainst = getmicrotime;
$|=1;
main();
my $mainet = getmicrotime;
printf("Total time required: %2.3fs\n\n",$mainet-$mainst);
exit 0;

###############################################################################
# Main entry function:
###############################################################################

sub main()
  {
  my $help = 0;
  my $man = 0;
  my $backfile;

  printf("\nSGLBackup V%s by Sascha 'SieGeL' Pfalz\n\n",VER);
  GetOptions ('help|?'          => \$help, 
              'man'             => \$man,
              'config|f=s'      => \$cfgfile,
              'backupset|b=s'   => \$bsets ) or pod2usage(2);
  pod2usage(1) if $help;
  pod2usage(-exitstatus => 0, -verbose => 2) if $man;
  $cfg = ReadConfig($cfgfile);
  if(!defined($cfg))
    {
    exit 10;
    }
  if($bsets eq '-1')
    {
    printf("Make backup of all %d Sets, please wait.\n\n",$cfg->{'maxsets'});
    for(my $i = 0; $i < $cfg->{'maxsets'}; $i++)
      {
      if($cfg->{'dir'}[$i] ne '')
        {
        $backfile = TarAndZipSet($i);  
        if(defined($backfile) && $backfile ne '')
          {
          ProcessBackup($backfile,$i);
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
        printf("ERROR: Set number %s out of range (Allowed is 0-%d)!\n\n",$params[$i],$cfg->{'maxsets'}-1);
        exit 10;
        }  
      }
    for(my $i = 0; $i < scalar @params; $i++)
      {
      $backfile = TarAndZipSet($params[$i]);
        if(defined($backfile) && $backfile ne '')
        {
        ProcessBackup($backfile,$params[$i]);
        }
      }
    }
  }

###############################################################################
# Processes on the backupped file according to settings for the passed setnr
###############################################################################

sub ProcessBackup($$)
  {
  my ($bfile,$setnr) = @_;  
  my @dummy;
  
  @dummy = split(/,/,$cfg->{'mode'}[$setnr]);
  for(my $i = 0; $i < scalar @dummy; $i++)
    {
    if($dummy[$i] eq 'fcopy')
      {
      printf("Copying file to %s...",$cfg->{'dest'}[$setnr]);
      my $rc = copy($bfile, $cfg->{'dest'}[$setnr]);
      if(!$rc)
        {
        printf("FAILED!\nError while copying backupfile: %s\n\n",$!);
        return(1);
        }  
      print("done.\n");
      next;
      }  
    if($dummy[$i] eq 'ftp')
      {
      $cfg->{'ftp'}[$setnr]=~/(.*)(\:)(.*)(@)(.*)/;
      my $ftpuser = $1;
      my $ftppass = $3;
      my $ftphost = $5;  
      if($ftpuser eq '' || $ftppass eq '' || $ftphost eq '')
        {
        printf("FTP: Logindata %s invalid, check settings!\n\n",$cfg->{'ftp'}[$setnr]);
        return(2);
        }
      printf("Sending file to %s: ",$ftphost);
      if(!UploadFTP($ftpuser,$ftppass,$ftphost,$bfile,$setnr))
        {
        return(3);
        }
      print("done.\n\n");
      }
    } 
  unlink($bfile);
  return(0);
  }

###############################################################################
# Uploads $bfile to given FTP server
###############################################################################


sub UploadFTP($$$$$)
  {
  my ($fuser,$fpass,$fhost,$bfile,$setnr) = @_;
  my $ftp; 
  my @hostdata = split(/\:/,$fhost);
  if(!defined($hostdata[1])) 
    {
    $hostdata[1] = '21';  # Default port is 21
    }
  eval
    {
    $ftp = Net::FTP->new($hostdata[0], Debug => 0, Port => $hostdata[1]) or die "$@";
    };
  if($@)
    {
    $@=~/(.*)(at.*)/i;
    print("FAILED: Reason: $1\n\n");
    return(0);
    }
  if(!$ftp->login($fuser,$fpass))
    {
    print("FAILED!\nFTP-Server says: ".$ftp->message."\n");
    $ftp->quit;
    return(0);
    }
  if($cfg->{'ftpdir'}[$setnr] ne '')
    {
    if(!$ftp->cwd($cfg->{'ftpdir'}[$setnr]))
      {
      print("cwd() failed!\nFTP-Server says: ".$ftp->message."\n");
      $ftp->quit;
      return(0);
      }
    } 
  $ftp->binary;
  $ftp->put($bfile,basename($bfile));
  $ftp->quit;
  return(1);
  }

###############################################################################
# Creates the tar.gz file for passed set number 
# V0.2: Checks first if directory definition contains oracle export, in this
#       case we branch to the corresponding function and return the result of it.
###############################################################################

sub TarAndZipSet($)
  {
  my ($setnr) = @_;
  my $targetname;

  printf("Processing Set #%d (%s)...",$setnr,$cfg->{'name'}[$setnr]);
  my $data = $cfg->{'dir'}[$setnr];
  if($data=~/^ORACLE\:/)
    {
    return(ExportOracle($setnr));    
    }
  my $st = getmicrotime;
  if(!-d $cfg->{'dir'}[$setnr] || !-R $cfg->{'dir'}[$setnr])
    {
    printf("FAILED!\n'%s': %s!\n\n",$cfg->{'dir'}[$setnr],strferror());
    return(undef);
    }  
  if(!-d $cfg->{'tmpdir'} || !-w $cfg->{'tmpdir'})
    {
    printf("FAILED!\nTempdir '%s' does not exist or is not writeable!\n\n",$cfg->{'tmpdir'});
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
  my $cmd = sprintf("%s -cf %s.tar %s >/dev/null 2>&1",$cfg->{'tar'},$targetname,$cfg->{'dir'}[$setnr]);
  system($cmd);
  if ($? == -1) 
    {
    print("FAILED!!!\nReason: $!\n\n");
    return(undef);
    }
  elsif ($? & 127) 
    {
    printf("FAILED!!!\n%s died with signal %d, %s coredump\n\n",$cfg->{'tar'},($? & 127),  ($? & 128) ? 'with' : 'without');
    return(undef);
    }
  else 
    {
    if(($? >> 8) > 0) 
      {
      printf("FAILED!!!\n%s exited with value %d\n\n",$cfg->{'tar'}, $? >> 8);
      unlink($targetname.'.tar');
      return(undef);
      }
    }
  # And GZIP the file:
  print(".");
  $cmd = sprintf("%s %s.tar >/dev/null 2>&1",$cfg->{'gzip'},$targetname);
  system($cmd);
  if ($? == -1) 
    {
    print("FAILED!!!\nReason: $!\n\n");
    return(undef);
    }
  elsif ($? & 127) 
    {
    printf("FAILED!!!\n%s died with signal %d, %s coredump\n\n",$cfg->{'gzip'},($? & 127),  ($? & 128) ? 'with' : 'without');
    return(undef);
    }
  else 
    {
    if(($? >> 8) > 0) 
      {
      printf("FAILED!!!\n%s exited with value %d\n\n",$cfg->{'gzip'}, $? >> 8);
      unlink($targetname.'.tar.gz');
      return(undef);
      }
    }
  my $et = getmicrotime;
  printf("done (%2.3fs).\n",$et-$st);
  return($targetname.'.tar.gz');
  }

###############################################################################
# Sub Function to read and parse the configuration 
###############################################################################

sub ReadConfig($)
  {
  my ($fname) = @_;
  my $cfg;
  my $config;
  
  eval
    {
    $cfg = Config::IniFiles->new(-file => $fname, -nocase => 1) || die "\n"; # Try to load in our configfile
    $config->{'gzip'}         = $cfg->val('COMMAND','GZIP') || die "Errors in $fname: No 'GZIP' tag defined!\n"; 
    $config->{'tar'}          = $cfg->val('COMMAND','TAR') || die "Errors in $fname: No 'TAR' tag defined!\n"; 
    $config->{'tmpdir'}       = $cfg->val('COMMAND','TMPDIR');
    $config->{'maxsets'}      = $cfg->val('BACKUP_SETS','MAX_SETS') || die "Errors in $fname: No MAX_SETS tag defined!\n";
    for(my $i = 0; $i < $config->{'maxsets'}; $i++)
      {
      $config->{'dir'}[$i]    = $cfg->val('BACKUP_SETS','DIR_'.$i);  
      $config->{'name'}[$i]   = $cfg->val('BACKUP_SETS','NAME_'.$i);  
      $config->{'mode'}[$i]   = lc($cfg->val('BACKUP_SETS','MODE_'.$i));
      $config->{'dest'}[$i]   = $cfg->val('BACKUP_SETS','DEST_'.$i);        
      $config->{'ftp'}[$i]    = $cfg->val('BACKUP_SETS','FTP_'.$i);        
      $config->{'ftpdir'}[$i] = $cfg->val('BACKUP_SETS','FTP_DEST_'.$i);        

      my @test = split(/,/,$config->{'mode'}[$i]);
      for(my $a =0; $a < scalar @test; $a++)
        {
        if($test[$a] eq 'fcopy' && ( !defined($config->{'dest'}[$i]) || $config->{'dest'}[$i] eq ''))
          {
          die("CFG-ERROR: BackupSet #$i has FCOPY mode defined but no destination set!");
          }  
        if($test[$a] eq 'ftp' && (!defined($config->{'ftp'}[$i]) || $config->{'ftp'}[$i] eq ''))
          {
          die("CFG-ERROR: BackupSet #$i has FTP mode defined but no FTP data given!!");
          }
        } 
      }
    };
  if($@)
    {
    $@=~s/(.*)(at.*)/$1/g;
    chop($@);    
    printf("%s\n\n",$@);
    return(undef);
    }
  if($config->{'tmpdir'} eq '')
    {
    $config->{'tmpdir'} = '/tmp';
    }
  if(!-X $config->{'tar'})
    {
    printf("CFG: '%s' is not executable!!\n\n",$config->{'tar'});
    return(undef);
    }
  my @testfile = split(/ /,$config->{'gzip'});
  if(!-X $testfile[0])
    {
    printf("CFG: '%s' is not executable!!\n\n",$testfile[0]);
    return(undef);
    }
  return($config);
  }

###############################################################################
# Determines seconds + microseconds. Used to measure processing speeds.
###############################################################################

sub getmicrotime
  {
  my ($sec,$usec) = gettimeofday;
  return(sprintf("%d.%d",$sec,$usec));
  }

###############################################################################
# Exports an Oracle Database with the help of exp
###############################################################################

sub ExportOracle($)
  {
  my ($setnr) = @_;  

  my $st = getmicrotime;
  my $schema = "";
  my $data = $cfg->{'dir'}[$setnr];
  
  my @dummy = split /\|/,$data;
  if(defined($dummy[1]) && $dummy[1] ne '')
    {
    $schema = $dummy[1];
    }
  my $oralogin = $dummy[0];
  $oralogin=~s/ORACLE://;
  if(!defined($ENV{'ORACLE_HOME'}))
    {
    print("FAILED!\n\nERROR: ORACLE_HOME environment variable not found!\n\n");
    return(undef);
    }
  my $oraexport = sprintf("%s/bin/exp",$ENV{'ORACLE_HOME'});
  if(!-x $oraexport)
    {
    print("FAILED!\n\nERROR: Oracle Export not found / not executable!\n\n");
    return(undef);
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
    $cmdline = sprintf("%s USERID=%s FILE=%s LOG=%s FULL=Y ROWS=Y INDEXES=Y CONSISTENT=Y >/dev/null 2>&1",$oraexport,$oralogin,$targetname,$targetlog);
    }    
  else
    {
    $cmdline = sprintf("%s USERID=%s FILE=%s LOG=%s OWNER=%s ROWS=Y INDEXES=Y CONSISTENT=Y >/dev/null 2>&1",$oraexport,$oralogin,$targetname,$targetlog,$schema);
    }
  system($cmdline);
  if ($? == -1) 
    {
    print("FAILED!!!\nReason: $!\n\n");
    unlink($targetname);
    unlink($targetlog);
    return(undef);
    }
  elsif ($? & 127) 
    {
    printf("FAILED!!!\nexp died with signal %d, %s coredump\n\n",($? & 127),  ($? & 128) ? 'with' : 'without');
    unlink($targetname);
    unlink($targetlog);
    return(undef);
    }
  else 
    {
    if(($? >> 8) > 0) 
      {
      printf("FAILED!!!\nexp exited with value %d\n\n", $? >> 8);
      unlink($targetname);
      unlink($targetlog);
      return(undef);
      }
    }
  # And TAR/GZIP the file:
  print(".");
  my $tarname = sprintf("%s/%s_%4d%02d%02d_%02d%02d%02d",$cfg->{'tmpdir'},$cfg->{'name'}[$setnr],$myyear,($tiarray[4]+1),$tiarray[3],$tiarray[2],$tiarray[1],$tiarray[0]);
  my $cmd     = sprintf("%s -cf %s.tar %s %s >/dev/null 2>&1",$cfg->{'tar'},$tarname,$targetname,$targetlog);
  system($cmd);
  if ($? == -1) 
    {
    print("FAILED!!!\nReason: $!\n\n");
    unlink($targetname);
    unlink($targetlog);
    return(undef);
    }
  elsif ($? & 127) 
    {
    printf("FAILED!!!\n%s died with signal %d, %s coredump\n\n",$cfg->{'tar'},($? & 127),  ($? & 128) ? 'with' : 'without');
    unlink($targetname);
    unlink($targetlog);
    return(undef);
    }
  else 
    {
    if(($? >> 8) > 0) 
      {
      printf("FAILED!!!\n%s exited with value %d\n\n",$cfg->{'tar'}, $? >> 8);
      unlink($tarname.'.tar');
      unlink($targetname);
      unlink($targetlog);
      return(undef);
      }
    }
  # And GZIP the file (removing first the original files to save space):
  print(".");
  unlink($targetname);
  unlink($targetlog);
  $cmd = sprintf("%s %s.tar >/dev/null 2>&1",$cfg->{'gzip'},$tarname);
  system($cmd);
  if ($? == -1) 
    {
    print("FAILED!!!\nReason: $!\n\n");
    unlink($tarname.'.tar');
    return(undef);
    }
  elsif ($? & 127) 
    {
    printf("FAILED!!!\n%s died with signal %d, %s coredump\n\n",$cfg->{'gzip'},($? & 127),  ($? & 128) ? 'with' : 'without');
    unlink($tarname.'.tar');
    return(undef);
    }
  else 
    {
    if(($? >> 8) > 0) 
      {
      printf("FAILED!!!\n%s exited with value %d\n\n",$cfg->{'gzip'}, $? >> 8);
      unlink($tarname.'.tar.gz');
      unlink($tarname.'.tar');
      return(undef);
      }
    }
  my $et = getmicrotime;
  printf("done (%2.3fs).\n",$et-$st);
  return($tarname.'.tar.gz');
  }

__END__

=head1 NAME

SGLBackup.pl - Configurable backupper for various projects

=head1 SYNOPSIS

SGLBackup.pl [options]

 Options:
   --help      brief help message
   --man       full documentation
   --config    Alternative configfile (default is config.ini)
   --backupset Number of backupset to process (default is all)

=head1 OPTIONS

=over 12

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

=back

=head1 DESCRIPTION

This script will take a number of directories, tars one by one
and compress it with your favourite packer. Finally the packed
files can be sent via FTP, copied to an backup device etc.

=head1 REQUIREMENTS

The following additional Perl modules are required for operation
of this script:

=over 1

=item L<Config::IniFiles> 

=item L<Getopt::Long>    

=item L<Pod::Usage>     

=item L<Time::HiRes> 

=item L<Net::FTP> 

=item L<File::Copy> 

=back

You can get them from L<http://www.cpan.org> or it's mirrors.

=head1 CONFIGURATION

The configuration of SGLBackup is done via a plain textfile.
You can use the B<#> sign for comments. Parameters are always
given in the following form:

C<key = value>

These keywords are grouped in sections for better overview.
Section names are enclosed in square brackets B<[]> and all
according keywords have to follow after the section name.

Currently, the following keywords and sections are known to 
SGLBackup:

=over 3

=item B<[COMMAND]>

=over 2

=item B<TAR = (path_to_program)>

Defines the full path to your tar program. The script calls
tar with the parameters B<-cf> (create new file), this should
work with almost every tar around. If you run into trouble 
because of these parameters plz inform me and I will add the
parameter options as additional keyword to the configuration
file.

=item B<GZIP = (path_to_program_with_params)>

Defines the full path to your favourite packer program
B<INCLUDING> all options required for your packer to force the
packer to overwrite existing files (i.e. --force) and which
packing ratio should be used (i.e. --best).

=item B<TMPDIR = (path)>

You may specify a directory the script should use as temporary
directory. If you leave out this parameter the script tries to
use B</tmp>.

=back

=item B<[BACKUP_SETS]>

=over 2

=item B<MAX_SETS = (max. number of sets)>

=back

=back

=head1 AUTHOR

Written and (c) 2003-2004 by Sascha 'SieGeL' Pfalz <webmaster@saschapfalz.de>

This is fully public domain, do what you want with it.

Exception to this public licence is the SCO Group, 
which has NO RIGHT TO USE this software and it is 
FORBIDDEN FOR ANY MEMBER OF THE SCO GROUP to use 
this code, else they have to pay my special Licence 
fee for only B<$1000 per year>, payable for every 
instance of this tool and of course for every member
who uses it.

=head1 VERSION

This is SGLBackup.pl B<V0.2>

=head1 HISTORY

=over 2

=item B<V0.2  (07-Dec-2004)>

Added Oracle export functionality. This allows to perform
logical exports of given schemata or the full database.

=item B<V0.1  (14-Nov-2003)>

Initial Version. 

=back

=cut
