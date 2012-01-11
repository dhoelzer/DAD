#######################################################################
#
# FileACL - Utility to translate ACL hex to Win32 Constant names.
# 
# Version: 0.1
# Date: 2004-12-10
# Author: Jason Kiebzak
#######################################################################
package FileACL;
use strict;


BEGIN {
    use Exporter;

    my @ISA       = qw( Exporter );
    my @EXPORT_OK = qw( &ConvertFolderACL &ConvertFileACL &ConvertDumpSecFile &ConvertDumpSecDir );
    my @EXPORT    = qw(  );
}


#####################
## Global Vars
##
    my $VERSION = '0.1';

    my %DumpSecDecVals = ( 'R' => '1',
                           'W' => '2',
                           'X' => '32',
                           'D' => '65536',
                           'P' => '262144',
                           'O' => '524288'
                         );

    my %DumpSecFileConstVals = ( 'R' => 'FILE_READ_DATA',
                                 'W' => 'FILE_WRITE_DATA',
                                 'X' => 'FILE_EXECUTE',
                                 'D' => 'DELETE',
                                 'P' => 'WRITE_DAC',
                                 'O' => 'WRITE_OWNER'
                               );

    my %DumpSecDirConstVals = ( 'R' => 'FILE_LIST_DIRECTORY',
                                'W' => 'FILE_ADD_FILE',
                                'X' => 'FILE_TRAVERSE',
                                'D' => 'DELETE',
                                'P' => 'WRITE_DAC',
                                'O' => 'WRITE_OWNER'
                              );


###############################
## METHODS
##
    sub new{
        my $proto  = shift;
        my $class  = ref( $proto ) || $proto;
        my $self   = {};

        bless( $self, $class );
        
        $self;
    }



    ###############################
	##  $err = ConvertFolderACL( $BitMaskHex, \%OutConst );
	##      $BitMaskHex - string - hex string
	##      %OutConst   - hash   - flags set on the account have a value of one
	##      $err        - string - if its null, there was a problem; return of 1 means it was successful
	##
	sub ConvertFolderACL{
        my $self = shift;
		my ( $BitMask, $OutConst ) = @_;

        ( $BitMask ) = $BitMask=~/.x(.*)/;
        if( length($BitMask) != 8 ){
            $!=-1;
            print STDERR 'Error: incorrect ACL Bitmask format. Needs to be in the form: 0xnnnnnnnn';
            return undef;
        }
        $BitMask = hex( $BitMask );

		my %MaskBits = ( '0000000001' => 'FILE_LIST_DIRECTORY',
    	                 '0000000002' => 'FILE_ADD_FILE',
    	                 '0000000004' => 'FILE_ADD_SUBDIRECTORY',
        	             '0000000008' => 'FILE_READ_EA',
            	         '0000000016' => 'FILE_WRITE_EA',
                	     '0000000032' => 'FILE_TRAVERSE',
                	     '0000000064' => 'FILE_DELETE_CHILD',
	                     '0000000128' => 'FILE_READ_ATTRIBUTES',
    	                 '0000000256' => 'FILE_WRITE_ATTRIBUTES',
    	                 '0000065536' => 'DELETE',
        	             '0000131072' => 'READ_CONTROL',
            	         '0000262144' => 'WRITE_DAC',
                	     '0000524288' => 'WRITE_OWNER',
                	     '0000983040' => 'STANDARD_RIGHTS_REQUIRED',
                    	 '0001048576' => 'SYNCHRONIZE',
                    	 '0002031616' => 'STANDARD_RIGHTS_ALL',
            	         '0016777216' => 'ACCESS_SYSTEM_SECURITY',
            	         '0033554432' => 'MAXIMUM_ALLOWED',
            	         '0268435456' => 'GENERIC_ALL',
            	         '0536870912' => 'GENERIC_EXECUTE',
            	         '1073741824' => 'GENERIC_WRITE',
            	         '2147483648' => 'GENERIC_READ'
                	   );

	    my @Bits = keys %MaskBits;

	    foreach my $Bit ( sort {$b <=> $a} @Bits ){
    		if ( $BitMask - $Bit >= 0 ){
    			${$OutConst}{ $MaskBits{ $Bit } } = 1;
    			$BitMask = $BitMask - $Bit;
	    	}
    	}
	    return 1;

	}



    ###############################
	##  $err = ConvertFileACL( $BitMaskHex, \%OutConst );
	##      $BitMaskHex - string - hex string
	##      %OutConst   - hash   - flags set on the account have a value of one
    ##      $err        - string - if its null, there was a problem; return of 1 means it was successful
	##
	sub ConvertFileACL{
        my $self = shift;
		my( $BitMask, $OutConst ) = @_;

        ( $BitMask ) = $BitMask=~/.x(.*)/;
        if( length($BitMask) == 0 ){
            $!=-1;
            print STDERR 'Error: incorrect ACL Bitmask format. Needs to be in the form: 0xnnnnnnnn';
            return undef;
        }
        $BitMask = hex( $BitMask );

		my %MaskBits = ( '0000000001' => 'FILE_READ_DATA',
    	                 '0000000002' => 'FILE_WRITE_DATA',
    	                 '0000000004' => 'FILE_APPEND_DATA',
        	             '0000000008' => 'FILE_READ_EA',
            	         '0000000016' => 'FILE_WRITE_EA',
                	     '0000000032' => 'FILE_EXECUTE',
	                     '0000000128' => 'FILE_READ_ATTRIBUTES',
    	                 '0000000256' => 'FILE_WRITE_ATTRIBUTES',
    	                 '0000065536' => 'DELETE',
        	             '0000131072' => 'READ_CONTROL',
            	         '0000262144' => 'WRITE_DAC',
                	     '0000524288' => 'WRITE_OWNER',
                	     '0000983040' => 'STANDARD_RIGHTS_REQUIRED',
                    	 '0001048576' => 'SYNCHRONIZE',
                    	 '0002031616' => 'STANDARD_RIGHTS_ALL',
            	         '0016777216' => 'ACCESS_SYSTEM_SECURITY',
            	         '0033554432' => 'MAXIMUM_ALLOWED',
            	         '0268435456' => 'GENERIC_ALL',
            	         '0536870912' => 'GENERIC_EXECUTE',
            	         '1073741824' => 'GENERIC_WRITE',
            	         '2147483648' => 'GENERIC_READ'
                	   );
                   
	    my @Bits = keys %MaskBits;

	    foreach my $Bit ( sort {$b <=> $a} @Bits ){ 
    		if ( $BitMask - $Bit >= 0 ){
    			${$OutConst}{ $MaskBits{ $Bit } } = 1;
    			$BitMask = $BitMask - $Bit;
	    	}
    	}
	    return 1;

	}



    ###############################
	##  ConvertDumpSecFile( $DumpSec, \$OutHex, \%OutConst );
	##          $DumpSec  - string - DumpSec translated file rights - e.g. RXWD
	##          $OutHex   - string - hex string; e.g. 0x000000001
	##          %OutConst - hash   - keys are the constant permissions, values always equal 1
	##
	sub ConvertDumpSecFile{
        my $self = shift;
		my( $DumpSec, $OutHex, $OutConst ) = @_;
		my $tmpHex;

        if( $DumpSec=~/no access/ig ){
            ${$OutHex} = '0x00000000';
            ${$OutConst}{NO_ACCESS} = 1;
            return 1;
        }elsif( $DumpSec=~/^all$/i ){
            ${$OutHex} = '0x001f0000';
            ${$OutConst}{STANDARD_RIGHTS_ALL} = 1;
            return 1;
        }else{
            my @split = split//,$DumpSec;
            foreach( @split ){
                $tmpHex = $tmpHex + $DumpSecDecVals{$_};
                ${$OutConst}{ $DumpSecFileConstVals{$_} } = 1;
            }
            $tmpHex = sprintf "%lx",$tmpHex;
            while( length($tmpHex) < 8 ){
                $tmpHex = '0' . $tmpHex;
            }
            $tmpHex = '0x' . $tmpHex;
            ${$OutHex} = $tmpHex;
            return 1;
        }

	}



    ###############################
	##  ConvertDumpSecDir( $DumpSec, \$OutHex, \%OutConst );
	##          $DumpSec  - string - DumpSec translated directory rights - e.g. RXWD
	##          $OutHex   - string - hex string; e.g. 0x000000001
	##          %OutConst - hash   - keys are the constant permissions, values always equal 1
	##
	sub ConvertDumpSecDir{
        my $self = shift;
		my( $DumpSec, $OutHex, $OutConst ) = @_;
		my $tmpHex;

        if( $DumpSec=~/no access/ig ){
            ${$OutHex} = '0x00000000';
            ${$OutConst}{NO_ACCESS} = 1;
            return 1;
        }elsif( $DumpSec=~/^all$/i ){
            ${$OutHex} = '0x001f0000';
            ${$OutConst}{STANDARD_RIGHTS_ALL} = 1;
            return 1;
        }else{
            my @split = split//,$DumpSec;
            foreach( @split ){
                $tmpHex = $tmpHex + $DumpSecDecVals{$_};
                ${$OutConst}{ $DumpSecDirConstVals{$_} } = 1;
            }
            $tmpHex = sprintf "%lx",$tmpHex;
            while( length($tmpHex) < 8 ){
                $tmpHex = '0' . $tmpHex;
            }
            $tmpHex = '0x' . $tmpHex;
            ${$OutHex} = $tmpHex;
            return 1;
        }

	}



############
#Property flag                                                       hex        decimal 

## (bits 0-15)
#FILE_READ_DATA (file) or FILE_LIST_DIRECTORY (directory)            0x00000001          1 
#FILE_WRITE_DATA (file) or FILE_ADD_FILE (directory)                 0x00000002          2 
#FILE_APPEND_DATA (file) or FILE_ADD_SUBDIRECTORY (directory)        0x00000004          4
#FILE_READ_EA                                                        0x00000008          8 
#FILE_WRITE_EA                                                       0x00000010         16 
#FILE_EXECUTE (file) or FILE_TRAVERSE (directory)                    0x00000020         32 
#FILE_DELETE_CHILD (directory)                                       0x00000040         64 
#FILE_READ_ATTRIBUTES                                                0x00000080        128 
#FILE_WRITE_ATTRIBUTES                                               0x00000100        256 
#DELETE                                                              0x00010000      65536
#READ_CONTROL                                                        0x00020000     131072
#WRITE_DAC                                                           0x00040000     262144
#WRITE_OWNER                                                         0x00080000     524288
#SYNCHRONIZE                                                         0x00100000    1048576

## 
#STANDARD_RIGHTS_REQUIRED                                            0x000f0000     983040
#    (above combines DELETE, READ_CONTROL, WRITE_DAC, and WRITE_OWNER access)  
#STANDARD_RIGHTS_ALL                                                 0x001f0000    2031616
#    (above combines DELETE, READ_CONTROL, WRITE_DAC, WRITE_OWNER, and SYNCHRONIZE access)

## (bits 24,25)
#ACCESS_SYSTEM_SECURITY                                              0x01000000   16777216
#MAXIMUM_ALLOWED                                                     0x02000000   33554432

## (bits  28-31 ) Processes running in the local system account are granted these
#GENERIC_ALL                                                         0x10000000  268435456
#GENERIC_EXECUTE                                                     0x20000000  536870912
#GENERIC_WRITE                                                       0x40000000 1073741824
#GENERIC_READ                                                        0x80000000 2147483648



#################################################################################
## DumpSec letter abbreviations
#
#DIR column (used for directories only)
#
#R	Account can list the contents of the directory.
#W	Account can add new files and subdirectories to the directory.
#X	Account can traverse the directory as part of a path.
#D	Account can delete the entire directory.
#P	Account can change permissions for the directory and all files and subdirectories.
#O	Account can change ownership of the directory.
#All	Same as RWXDPO.
#No access	Account is denied all access to directory.
#
#
#FILE column (used for directories and files)
#
#R	Account can read the file.
#W	Account can write to the file.
#X	Account can execute the file. 
#D	Account can delete the file.
#P	Account can change permissions for the file.
#O	Account can change ownership of the file.
#All	Same as RWXDPO.
#No access	Account is denied all access to file.
