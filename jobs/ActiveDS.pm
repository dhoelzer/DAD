#######################################################################
#
# ActiveDS - Utility to help translate Active Directory fields.
# 
# Version: 0.4
# Date: 2004 Sep 9
# Author: Jason Kiebzak
# Updated: 2005 Jan 12
# Updated: 2005 Jun 08
#
# To do:
#   - make a name translation function
#   - option to convert UTC dates or not; perhaps set this option on the main object, thus be a global switch
#     - need another sub to translate between time zones?
#
#######################################################################
package ActiveDS;
use strict;

use Net::Domain;
use Net::LDAP;
use Net::Ping;

my $AccountsFile;
my $DomainName;
my $LDAP;
my $LDAPDomainName;
my $LDAPmsg;


BEGIN {
    use Exporter;

    my @ISA       = qw( Exporter );
    my @EXPORT_OK = qw( &GetEffectivePerm &ConvertSidToString );
    my @EXPORT    = qw(  );
}



#####################
## Global objects
##
  my $domain_name; ## to be deleted;



#####################
## Global Vars
##
    my $VERSION = '0.5';
    my $LDAP;



###############################
## PRIVATE METHODS
##
  #####################
  ##  my %options = &$_import_options( @options );
  ##
  ##  - Expecting an array, where even number are element names, and odd are values
  ##  - Will upper case keys, but leave values
  ##    - keys should always be than name of your option that you are importing
  ##
    my $_import_options = sub {
        my %options = @_;
        my $k;
        my $v;

        while( ($k, $v) = each %options ){
            delete $options{ $k };
            $options{ uc($k) } = $v;
        }

        %options;
    };



###############################
## PUBLIC METHODS
##
  #####################
  ##  $obj = new( [$Domain][, $DistinguishedName][, $Password] );
  ##     $AccountsFile      - string - full path to accounts file (see GetAuthenAccount() for more details)
  ##                                     The first time ActiveDS::new is called, you must provide a path to a valid Acccounts File.
  ##                                      Each subsequent time ActiveDS::new is called, it will use the most recently provided path
  ##                                      to an $AccountsFile. Each time you provide a new path to an Accounts File, it will store
  ##                                      this as the 'most recent'.
  ##     $Domain            - string - domain to bind against. Expecting 'my.domain.com'
  ##     $DistinguishedName - string - fully distinguished name of account to use to bind against the directory service
  ##     $Password          - string - password for the account named by $DistinguishedName
  ##     $obj               - objref - ActiveDS object. use $obj->{LDAP} to spin custom queries
  ##
    sub new{
        my $proto  = shift;
        my $file;
        my $domain;
        my $class  = ref( $proto ) || $proto;

        my @dc;
        my $dn;
        my $pw;
        my $self   = {};
        my $tmp;
        my $tmp1;
        my $tmp2;
        my @tmp;

        eval{ $proto->{ACCOUNTS_FILE} };

        if( $@ ){
            ## This is the first time its been loaded since $self is not an object yet
            $domain = shift || Net::Domain::hostdomain();
            $dn     = shift;
            $pw     = shift;
        }else{
            # loaded before, thus we can either use what is passed in or the previous settings
            $domain = shift || $proto->{DOMAIN_NAME};
            $dn     = shift || $proto->{USERNAME_DN};
            $pw     = shift || $proto->{PASSWORD};
        }

        if( $dn eq '' || $pw eq '' ){
            ( $dn, $pw ) = GetAuthenAccount( 'ldap', $file );   ## this will die if $file is not valid
        }

        $self->{ACCOUNTS_FILE} = $file;
        $self->{DOMAIN_NAME}   = uc( $domain );     #my.domain.com; have to query for qualified domain name in order to bind against it; Net::LDAP requuires a domain name to bind against
        $self->{LDAP}          = Net::LDAP->new( $self->{DOMAIN_NAME} ) or die "$@";
        $tmp                   = $self->{LDAP}->bind( $dn, password => $pw );
        $self->{USERNAME_DN}   = $dn;
        $self->{USERNAME_SAM}  = '';    #have to query for this; we set this value down below
        $self->{PASSWORD}      = $pw;
        $self->{ERR}           = ${$tmp}{errorMessage};
        $self->{PING}          = Net::Ping->new('','1');

        $self->{CONFIGURATION_LDAP}    = '';
        $self->{DOMAIN_NAME_LDAP}      = '';
        $self->{DOMAIN_NAME_SAM}       = '';
        $self->{DOMAIN_SID}            = '';
        $self->{ROOT_DOMAIN_NAME}      = '';
        $self->{ROOT_DOMAIN_NAME_LDAP} = '';
        $self->{ROOT_DOMAIN_NAME_SAM}  = '';
        $self->{ROOT_DOMAIN_SID}       = '';
        $self->{SAMBA}                 = '';         #will be set to '1' if its detected as running; currently set in GetLocalMember();
        $self->{SCHEMA_LDAP}           = '';
        $self->{USERNAME_SAM}          = '';

        bless( $self, $class );

        ## return object with bind error if bind doesn't succeed
        if( $self->{ERR} ne '' ){
            return $self;
        }

        ##Configuration LDAP - CN=Configuration,DC=domin,DC=net
        ##Domain Name LDAP - DC=my,DC=domain,DC=net
        ##Root Domain Name LDAP - DC=domain,DC=net
        ##Schema LDAP - CN=Schema,CN=Configuration,DC=domin,DC=net
        $tmp = $self->{LDAP}->root_dse( attrs => ('rootDomainNamingContext','schemaNamingContext','configurationNamingContext','defaultNamingContext') );
        ( $self->{CONFIGURATION_LDAP} )    = uc( $tmp->get_value( 'configurationNamingContext' ) );
        ( $self->{DOMAIN_NAME_LDAP} )      = uc( $tmp->get_value( 'defaultNamingContext' ) );
        ( $self->{ROOT_DOMAIN_NAME_LDAP} ) = uc( $tmp->get_value( 'rootDomainNamingContext' ) );
        ( $self->{SCHEMA_LDAP} )           = uc( $tmp->get_value( 'schemaNamingContext' ) );
        $tmp = '';

        ##Domain Name SAM - mydomain
        $tmp = $self->{LDAP}->search(
            base    => "CN=Partitions,$self->{CONFIGURATION_LDAP}",
            scope   => 'subtree',
            filter  => "(nCName=$self->{DOMAIN_NAME_LDAP})",
            attrs   => ['cn']
        );
        $tmp = $tmp->as_struct;
        foreach ( keys %{$tmp} ){
            $self->{DOMAIN_NAME_SAM} = uc( ${${$tmp}{$_}}{cn}[0] );
            last;
        }

        ##Domain Sid - S-1-xxx...
        $tmp = $self->{LDAP}->search(
            base    => "$self->{DOMAIN_NAME_LDAP}",
            scope   => 'subtree',
            filter  => "(& (samaccountname=domain users) (objectclass=group) )",
            attrs   => ['objectsid']
        );
        $tmp = $tmp->as_struct;
        foreach ( keys %{$tmp} ){
            $self->{DOMAIN_SID}     = ConvertSidToSidString( $self, ${${$tmp}{$_}}{objectsid}[0] );     # have to pass $self in since it isn't blessed yet
            ( $self->{DOMAIN_SID} ) = $self->{DOMAIN_SID}=~/(.*)-\d+$/;
            last;
        }

        ##Root Domain Name SAM - mydomain
        ##Root Domain Name     - my.domain.com
        $tmp = $self->{LDAP}->search(
            base    => "CN=Partitions,$self->{CONFIGURATION_LDAP}",
            scope   => 'subtree',
            filter  => "(nCName=$self->{ROOT_DOMAIN_NAME_LDAP})",
            attrs   => ['cn','dnsRoot']
        );
        $tmp = $tmp->as_struct;
        foreach ( keys %{$tmp} ){
            $self->{ROOT_DOMAIN_NAME_SAM} = uc( ${${$tmp}{$_}}{cn}[0] );
            $self->{ROOT_DOMAIN_NAME}     = uc( ${${$tmp}{$_}}{dnsroot}[0] );
            last;
        }
        $tmp = '';

        ##Root Domain Sid - S-1-xxx...
        ##First, need to fetch root domain DCs and then figure out which DC is up and then specifically bind to the DC that is up
        ##  We're doing this extra step of binding to a specific DC because the 'primary DC' has gone down and this bind has
        ##    has failed on use because of this. If we bind to a specifice DC, which we know is up, then the bind will not fail.
        ##    When there issue occured before, I don't know why the bind did not roll over to the secondary DC, but the fact is
        ##    that is didnt' roll over, so we're making the bind more robust.
        ##Second, we'll drop the old bind before binding to the root domain
        ##Third, we'll bind back our current domain
        $self->get_dcs( \@dc, scope => 'root', fqn => '1' );
        $self->unbind();
        

        foreach my $dc ( @dc ){
            if( $self->{PING}->ping($dc,4) ){
                my $cnt = 0;
                while( $cnt < 5 ){
                    $tmp = Net::LDAP->new( $dc, timeout => 4 );
                    last if $tmp;
                    $cnt++;
                }
            }
        }
        $tmp->bind( $dn, password => $pw );
        $tmp1 = $tmp->search(
            base    => "$self->{ROOT_DOMAIN_NAME_LDAP}",
            scope   => 'subtree',
            filter  => "(& (samaccountname=domain users) (objectclass=group) )",
            attrs   => ['objectsid']
        );
        $tmp2 = $tmp1->as_struct;
        foreach ( keys %{$tmp2} ){
            $self->{ROOT_DOMAIN_SID}     = ConvertSidToSidString( $self, ${${$tmp2}{$_}}{objectsid}[0] );     # have to pass $self in since it isn't blessed yet
            ( $self->{ROOT_DOMAIN_SID} ) = $self->{ROOT_DOMAIN_SID}=~/(.*)-\d+$/;
            last;
        }
        $tmp->unbind;
        $tmp  = '';
        $tmp1 = '';
        $tmp2 = '';

        ##Bind back to our domain
        while( $self->{LDAP} eq '' ){
            $self->{LDAP} = Net::LDAP->new( $self->{DOMAIN_NAME} ) or die "$@";
        }
        $self->{LDAP}->bind( $dn, password => $pw );

        ##SAM account name for user we're binding as
        $tmp = $self->{LDAP}->search(
            base    => "$self->{USERNAME_DN}",
            scope   => 'subtree',
            filter  => '(objectclass=*)',
            attrs   => ['samaccountname']
        );
        $tmp = $tmp->as_struct;
        foreach ( keys %{$tmp} ){
            $self->{USERNAME_SAM} = uc( ${${$tmp}{$_}}{samaccountname}[0] );
            last;
        }

        $self;

    }


  #####################
  ##  $obj = unbind();
  ##   
    sub unbind{
        my $self = shift;

        $self->{LDAP}->unbind;
        $self->{LDAP}->disconnect;
        $self->{LDAP} = '';

        return 1;
    }



  #####################
  ##  $err = GetEffectivePerm( $DistinguishedName, \@ReturnedArray );
  ##        $DistinguishedName - string - fully qualified DN
  ##        \@ReturnedArray    - arrRef - will be filled with returned SamAccountNames
  ##        $err               - bit    - 1 for success; 0 for failure, check $self->{ERR} for returned errors on failures
  ##
    sub GetEffectivePerm{
        my $self = shift;
        my $UserDN = shift;
        my $ReturnedArray = shift;

        my %hash_ref;
        my $arr_ref;
        my $res;    ## results
        my $rec;    ## records

        if ( $UserDN!~/^CN\=/i | $UserDN!~/DC\=/ig ){
            $self->{ERR} = 'User reference is not a Distinguished Name';
            return 0;
        }

        $res = $self->{LDAP}->search(
            base    => $UserDN,
            scope   => "base",
            filter  => "(objectClass=user)",
            attrs   => ['tokengroups']
        );

        if ( ${$res}{errorMessage} ne '' ){
            $self->{ERR} = ${$res}{errorMessage};
            return 0;
        }

        $rec = $res->as_struct;

        foreach my $dn ( keys %{$rec} ){            #only one key, but need to 'loop' to grab it so that we have the proper upper case / lower case of string
            $arr_ref = ${${$rec}{$dn}}{tokengroups};
            last;
        }

        foreach my $sid ( @$arr_ref ){

            $sid = $self->ConvertToEncodedSid( $self->ConvertSidToSidString( $sid ) );

            $res = $self->{LDAP}->search(
                base    => $self->{DOMAIN_NAME_LDAP},
                scope   => "subtree",
                filter  => "(objectsid=$sid)",
                attrs   => ['samaccountname']
            );

            $rec = $res->as_struct;

            #only one key, but need to 'loop' to grab it so that we have the proper upper case / lower case of string
            #simply grabbing the samaccountname from the returned nested hashes and pushing it onto the array reference
            foreach my $dn ( keys %{$rec} ){    
                push @$ReturnedArray,${${$rec}{$dn}}{samaccountname}[0];
                last;
            }

        }

        return 1;

    }



  #####################
  ##  $err = GetMemberOf( $DistinguishedName, \@ReturnedArray );
  ##        IN  = $DistinguishedName - string; fully qualified DN
  ##              \@ReturnedArray - array reference; will be filled with returned SamAccountNames
  ##        OUT = $err - string; any error messages.
  ##
    sub GetMemberOf{
        my $self          = shift;
        my $DN            = shift;
        my $ReturnedArray = shift;

        my $arr_ref;
        my $res;
        my $rec;

        $res = $self->{LDAP}->search(
            base    => $DN,
            scope   => 'base',
            filter  => '(objectClass=*)',
            attrs   => ['memberof']
        );

        if ( ${$res}{errorMessage} ne '' ){
            $self->{ERR} = ${$res}{errorMessage};
            return 0;
        }

        $rec = $res->as_struct;

        foreach my $dn ( keys %{$rec} ){            #only one key, but need to 'loop' to grab it so that we have the proper upper case / lower case of string
            $arr_ref = ${${$rec}{$dn}}{memberof};
        }

        foreach my $Grp ( @{$arr_ref} ){
            $Grp=~/CN\=(.*),[CNOU]*=/i;
            push @{$ReturnedArray}, $1;
        }
    }



  #####################
  ##  $outGUID = ConvertGUID( $inGUID );
  ##        IN - string; GUID without hyphens, such as obtained from GUID property of the Active Directory object
  ##                    or GUID packed GUID (non alpha-numeric characters)
  ##        OUT - string; property hyphenated string in the form of: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
  ##
    sub ConvertGUID{
        my $self   = shift;
        my $inGUID = shift;

        my $return;

        if( $inGUID=~/\W/ ){
            $inGUID = unpack( 'h*', $inGUID );
        }

        $inGUID=~/(\w{8})(\w{4})(\w{4})(\w{4})(\w{12})/; #
        $return = $1 . '-' . $2 . '-' . $3 . '-' . $4 . '-' . $5;
        return $return;
    }



  ############################
  ##  $str = LogonHours( $HexValue );
  ##	      IN  - $HexValue is from the LogonHours property of the Active Directory object
  ##	      OUT - $str is a formated Day\Hours list. The hours are returned in UTC
  ##
    sub ConvertLogonHours {
        my $self = shift;
        my $val  = shift;

        my $ReturnFormatted;
        my %ReturnRaw;
        my @ReturnFormatted;

        my $hexdata = '';
        my $day     = 0;
        my $daypart = 1;

        if ( unpack('B*',$val) eq ('1'x168) ){
            return 'All';
        }elsif( unpack('B*',$val) eq ('0'x168) ){
			return 'None';
		}elsif( unpack('B*',$val) eq '' ){			#Null value = 'no restriction'
			return 'All';
		}

		my @Days  = ('Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday');

		for ( my $i = 0; $i < 21; $i++ ) {			# loops through the 21 hex values, which are in one string
			if ($i < length $val) {
				my $byte = substr($val, $i, 1);		# grabs each hex value
				my $bitdata = (unpack("B*", $byte));	# unpacks hex to bit
				if ( $daypart == 4 ){			# each day has three hex values; added all three values together, keeping each day's set of 3 separate from each other
					$day++;
					$daypart = 1;
				}
				$daypart++;

				while( length $bitdata > 0 ){							# chops the end bit off of the converted hex value and adds it to the stored value in the hash; basically reversing the order of the 8 bits
					$ReturnRaw{ $day } = $ReturnRaw{ $day } . chop $bitdata;		# each hash key represents a day;
				}
			}
		}

		foreach my $day ( keys %ReturnRaw ){
			my $raw = $ReturnRaw{$day};
			my $FirstHour;
			my $NextHour;

			for ( my $i = 0; $i < length $raw; $i++ ){
				my $bit = substr( $raw, $i, 1 );
				if ( $bit != 0 ){
					if ( $FirstHour ne '' ){
						if ( $NextHour ne '' ){
							my $tmpHour = $NextHour + 1;
							if ( $tmpHour == $i ){
								$NextHour = $i;
							}else{
								my $str = $ReturnFormatted[ $day ][1] . $FirstHour . ':00 - ' . ( $NextHour + 1 ) . ':00; ';
								$ReturnFormatted[ $day ] = [ $Days[$day], $str ];
								$FirstHour = '';
								$NextHour  = '';
							}
							undef $tmpHour;
						}else{
							$NextHour = $i;
						}
					}else{
						$FirstHour = $i;
					}
				} elsif ( $FirstHour != '' ){
					my $str = $ReturnFormatted[ $day ][1] . $FirstHour . ':00 - ' . ( $FirstHour + 1 ) . ':00; ';
					$ReturnFormatted[ $day ] = [ $Days[$day], $str ];
					$FirstHour = '';
					$NextHour  = '';
				}
			}
			if ( $NextHour > 0 ) {
				my $str = $ReturnFormatted[ $day ][1] . $FirstHour . ':00 - ' . ( $NextHour + 1 ) . ':00; ';
				$ReturnFormatted[ $day ] = [ $Days[$day], $str ];
			}
		}
		foreach my $line ( @ReturnFormatted ){
			$ReturnFormatted = $ReturnFormatted . "\n" if $ReturnFormatted ne '';
			$ReturnFormatted = $ReturnFormatted . ${$line}[0] . ' ' . ${$line}[1];
		}

		return $ReturnFormatted;
	}



  ###############################
  ##  $HashRef = UserAccountControl( $ControlBitMask );
  ##          IN  - Control Bit Mask. Should come from Useraccountcontrol property of the Active Directory object
  ##          OUT - Hash reference. Flags set on the account have a value of one. Other flags are set to zero.
  ##
    sub ConvertUserAccountControl{
        my $self = shift;
        my $BitMask = shift;

        my %return;

        my %MaskBits = ( '00000001' => 'SCRIPT',
    	                 '00000002' => 'ACCOUNTDISABLE',
        	             '00000008' => 'HOMEDIR_REQUIRED',
            	         '00000016' => 'LOCKOUT',
                	     '00000032' => 'PASSWD_NOTREQD',
                    	 '00000064' => 'PASSWD_CANT_CHANGE',
	                     '00000128' => 'ENCRYPTED_TEXT_PWD_ALLOWED',
    	                 '00000256' => 'TEMP_DUPLICATE_ACCOUNT',
        		         '00000512' => 'NORMAL_ACCOUNT',
                	     '00002048' => 'INTERDOMAIN_TRUST_ACCOUNT',
                    	 '00004096' => 'WORKSTATION_TRUST_ACCOUNT',
	                     '00008192' => 'SERVER_TRUST_ACCOUNT',
    	                 '00065536' => 'DONT_EXPIRE_PASSWORD',
        	             '00131072' => 'MNS_LOGON_ACCOUNT',
            	         '00262144' => 'SMARTCARD_REQUIRED',
                	     '00524288' => 'TRUSTED_FOR_DELEGATION',
                    	 '01048576' => 'NOT_DELEGATED',
	                     '02097152' => 'USE_DES_KEY_ONLY',
    	                 '04194304' => 'DONT_REQ_PREAUTH',
        	             '08388608' => 'PASSWORD_EXPIRED',
            	         '16777216' => 'TRUSTED_TO_AUTH_FOR_DELEGATION'
                	   );

        my @Bits = keys %MaskBits;

        foreach my $Bit ( sort {$b <=> $a} @Bits ){ 
            if ( $BitMask - $Bit >= 0 ){
                $return{ $MaskBits{ $Bit } } = 1;
                $BitMask = $BitMask - $Bit;
            }else{
                $return{ $MaskBits{ $Bit } } = '0';
            }
        }
        return \%return;

        ############
        #Property flag                    hex       decimal 
        #
        #SCRIPT                           0x0001    1 
        #ACCOUNTDISABLE                   0x0002    2 
        #HOMEDIR_REQUIRED                 0x0008    8 
        #LOCKOUT                          0x0010    16 
        #PASSWD_NOTREQD                   0x0020    32 
        #PASSWD_CANT_CHANGE               0x0040    64 
        #ENCRYPTED_TEXT_PWD_ALLOWED       0x0080    128 
        #TEMP_DUPLICATE_ACCOUNT           0x0100    256 
        #NORMAL_ACCOUNT                   0x0200    512 
        #INTERDOMAIN_TRUST_ACCOUNT        0x0800    2048 
        #WORKSTATION_TRUST_ACCOUNT        0x1000    4096 
        #SERVER_TRUST_ACCOUNT             0x2000    8192 
        #DONT_EXPIRE_PASSWORD             0x10000   65536 
        #MNS_LOGON_ACCOUNT                0x20000   131072 
        #SMARTCARD_REQUIRED               0x40000   262144 
        #TRUSTED_FOR_DELEGATION           0x80000   524288 
        #NOT_DELEGATED                    0x100000  1048576 
        #USE_DES_KEY_ONLY                 0x200000  2097152 
        #DONT_REQ_PREAUTH                 0x400000  4194304 
        #PASSWORD_EXPIRED                 0x800000  8388608 
        #TRUSTED_TO_AUTH_FOR_DELEGATION   0x1000000 16777216 
    }



  #####################
  ## $Date = Convert1601Date( $NanoSeconds | $HighDatePart, $LowDatePart );
  ##      IN  - $NanoSeconds - string - the nanosecond count pulled from Active Directory object. This the number of nanoseconds between now and January 1, 1601
  ##                           if input is '0' or '9223372036854775807' or '', the return is '0000-00-00 00:00:00'
  ##               or
  ##            $HighDatePart - string - obtained via ADO connection to AD. ADO slices the large interger AD value into two pieces
  ##            $LowDatePart  - string - obtained via ADO connection to AD. ADO slices the large interger AD value into two pieces
  ##                            formula for piecing this back together is $nanoseconds = ($HighDatePart * (2^32) + $LowDatePart )
  ##      OUT - string; formatted UTC date time - SQL friendly - yyyy-mm-dd hh:mm::ss
  ##
    sub Convert1601Date{
        my $self         = shift;
        my $nanoseconds = shift;

        my $i;

        if( $nanoseconds == 0 | $nanoseconds == 9223372036854775807 | $nanoseconds == 9223372036854775808 | $nanoseconds eq '' ){
#            return '1970-01-01 00:00:00';
            return '0000-00-00 00:00:00';
        }else{
            $nanoseconds = $nanoseconds * .0000001;			# Multiple times 1 nanoseconds
            $nanoseconds = $nanoseconds - 11644473600;		# Number of seconds between January 1, 1601 and January 1, 1970

            my @gmtime = gmtime( $nanoseconds );   # ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday);
            for( $i=0; $i <= 5; $i++ ){
                $gmtime[$i] = '0' . $gmtime[$i] if length($gmtime[$i]) == 1;
            }
            $gmtime[4] = ($gmtime[4]+1);
            $gmtime[4] = '0' . $gmtime[4] if length $gmtime[4] == 1;
            $gmtime[5] = ($gmtime[5]+1900);
            $nanoseconds = $gmtime[5] . "-$gmtime[4]-" . $gmtime[3] . " $gmtime[2]:$gmtime[1]:$gmtime[0]";
        }
        return $nanoseconds;
    }



  #####################
  ## $Date = Convert1970Date( $NanoSeconds );
  ##      IN  - $Seconds - string; the second count pulled from Active Directory object. This the number of seconds between now and January 1, 1970
  ##                       if input is '0' or '', the return is '0000-00-00 00:00:00'
  ##      OUT - string; formatted UTC date time - SQL friendly - yyyy-mm-dd hh:mm::ss
  ##
    sub Convert1970Date{
        my $self    = shift;
        my $seconds = shift;

        my $i;

        if( $seconds == 0 | $seconds eq '' ){
#            return '1970-01-01 00:00:00';
            return '0000-00-00 00:00:00';
        }else{
            my @gmtime = gmtime( $seconds );   # ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday);
            for( $i=0; $i <= 5; $i++ ){
                $gmtime[$i] = '0' . $gmtime[$i] if length($gmtime[$i]) == 1;
            }
            $gmtime[4] = ($gmtime[4]+1);
            $gmtime[4] = '0' . $gmtime[4] if length $gmtime[4] == 1;
            $gmtime[5] = ($gmtime[5]+1900);
            $seconds = $gmtime[5] . "-$gmtime[4]-" . $gmtime[3] . " $gmtime[2]:$gmtime[1]:$gmtime[0]";
        }
        return $seconds;
    }



  #####################
  ## $Date = ConvertGeneralizedTime( $GeneralizeTime );
  ##      IN  - $GeneralizeTime - string; YYYYMMDDHHMMSS.0[+/-/Z][HHMM]; e.g. - '20010928060000.0Z' or '20010928060000.0+0200', where Z indicates no time differential. If no time differential is specified, GMT is the default since Active Directory stores date/time GMT. 
  ##                              if input is equal '0' or '', the return is '0000-00-00 00:00:00'
  ##      OUT - string; formatted UTC date time; SQL friendly - yyyy-mm-dd hh:mm::ss
  ##
    sub ConvertGeneralizedTime{
        my $self    = shift;
        my $GenTime = shift;

        my $return;

        if( $GenTime == 0 | $GenTime eq '' ){
#            return '1970-01-01 00:00:00';
            return '0000-00-00 00:00:00';
        }else{
            my( $yr, $mn, $dy, $hr, $mi, $se, $dec, $def, $hdef, $mdef  ) = $GenTime=~/(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\.(\d{1})(.{0,1})(\d{0,2})(\d{0,2})/;
            if ( $yr eq '' ){
                #$return = "ERROR: Input should be in the GereralizedTime format: 'YYYYMMDDHHMMSS.0[+/-/Z][HHMM]'.\n"
                return;
            }elsif( $def!~/[z+-]/i ){
                $self->{ERR} = "Input should be in the GereralizedTime format: 'YYYYMMDDHHMMSS.0[+/-/Z][HHMM]'. Did you forget 'Z'?";
                return 0;
            }elsif( $def=~/z/i ){
                $return = "$yr-$mn-$dy $hr:$mi:$se";
            }elsif( $def eq '+' ){
                $hr = ( $hr + $hdef );
                $hr = '0' . $hr if length $hr == 1;
                $mi = ( $mi + $mdef );
                $mi = '0' . $mi if length $mi == 1;
                $return = "$yr-$mn-$dy $hr:$mi:$se";
            }elsif( $def eq '-' ){
                $hr = ( $hr - $hdef );
                $hr = '0' . $hr if length $hr == 1;
                $mi = ( $mi - $mdef );
                $mi = '0' . $mi if length $mi == 1;
                $return = "$yr-$mn-$dy $hr:$mi:$se";
            }
        }
        return $return;
    }


  #####################
  ## $Date = ConvertToGeneralizedTime( $GeneralizeTime );
  ##      IN  - string; formatted UTC date time; SQL friendly - [yy]yy-mm-dd[ hh:mm::ss]
  ##              - if a two digit yr is passed, it will assume that if the yr is greater than 50, 19xx is assumed, otherwise, 20xx is assumed.
  ##      OUT - $GeneralizeTime - string; YYYYMMDDHHMMSS.0[+/-/Z][HHMM]; e.g. - '20010928060000.0Z', where Z indicates no time differential. If no time differential is specified, GMT is the default since Active Directory stores date/time GMT. 
  ##
    sub ConvertToGeneralizedTime{
        my $self     = shift;
        my $DateTime = shift;

        my $return;

        my( $yr, $mn, $dy, $hr, $mi, $se, $ml, $part  ) = $DateTime=~/(\d{2,4})[\\\/\-](\d{1,2})[\\\/\-](\d{1,2})\s*(\d*):(\d*):(\d*)[\.:]*(\d*)\s*([apmAPM]{0,2})/;

        if( $yr eq '' ){
            $self->{ERR} = "Input should be in the Date/Time format: '[yy]yy-mm-dd[ hh:mm::ss]'.";
            return 0;
        }else{
            if( $hr < 12 && $part=~/p/ig ){
                $hr = $hr + 12;
            }elsif( $hr == 12 && $part=~/a/ig  ){
                $hr = '00';
            }
            if( length $yr != 4 ){
                if( $yr < 50 ){
                    $yr = '20' . $yr;
                }else{
                    $yr = '19' . $yr;
                }
            }
            if( length $mn != 2 ){
                $mn = '0' . $mn;
            }
            if( length $dy != 2 ){
                $dy = '0' . $dy;
            }
            if( length $hr != 2 ){
                $hr = '0' . $hr;
            }
            if( length $mi != 2 ){
                $mi = '0' . $mi;
            }
            if( length $se != 2 ){
                $se = '0' . $se;
            }
            $return = $yr . $mn . $dy . $hr . $mi . $se . '.0Z';
        }
          
        return $return;
    }


  #####################
  ## %Hash = GetFromAllDCs( $DN[, \@DCs] );
  ##      IN  - @DCs - fully qualified names of domain controllers to be queried - e.g. server.my.domain.net
  ##                 - if no DCs are specified, routine will use all DCs in forest
  ##                 - checks first value of @DCs to see if its NULL
  ##          - $DN - Distinguished Name to query against
  ##      OUT - a hash ref; keys will be PropertyName, value is PropertyValue
  ##            $Hash{ AccountExpires } = when the account expires; returned in UTC
  ##            $Hash{ LogonCount     } = total logon count from all DCs
  ##            $Hash{ LastLogon      } = newest logon time between the DCs; returned in UTC
  ##
    sub GetFromAllDCs{
        my $self = shift;
        my $DN   = shift;
        my $DCs  = shift;

        my $AccountExpires;
        my @gmtime;
        my %hash_ref;
        my $LogonCnt;
        my $LastLogon;
        my $LastLogonDC;

        if( $DN!~/^CN\=/i | $DN!~/DC\=/ig ){
            $self->{ERR} = 'User reference is not a Distinguished Name';
            return 0;
        }

        if( ${$DCs}[0] eq '' ){
            my @tmp;
            $self->get_dcs( \@tmp, fqn => 1 );
            $DCs = \@tmp;
        }

        foreach my $DC ( @{$DCs} ){
            my $objSrv;
            my $result;
            my $records;

            next if $DC eq '';
            
            ## have to rebind against each DC with credentials, but will not keep these connections as persistant
            $objSrv = $self->new( '', $DC );
            $result = $objSrv->{LDAP}->search( 
                base    => $DN,
                scope   => 'base',
                filter  => '(objectclass=*)',
                attrs   => ['lastlogon','logoncount','accountexpires']
            );
            $records = $result->as_struct;

            ## have to loop to fetch correct DN syntax (uppercase/lowercase, etc), even though there's only one return DN
            foreach my $DNtmp ( keys %{$records} ){
                $AccountExpires = ${${$records}{$DNtmp}}{accountexpires}[0];
                $LogonCnt = $LogonCnt + ${${$records}{$DNtmp}}{logoncount}[0];
                if( $LastLogon < ${${$records}{$DNtmp}}{lastlogon}[0] ){
                    $LastLogon =  ${${$records}{$DNtmp}}{lastlogon}[0];
                    $LastLogonDC = $DC;
                }
                last;
            }
            $objSrv->unbind();
        }

        $AccountExpires = $self->Convert1601Date( $AccountExpires );
        $LastLogon      = $self->Convert1601Date( $LastLogon );

        return ( 'LogonCount'     => $LogonCnt,
                 'LastLogon'      => $LastLogon,
                 'LastLogonDC'    => $LastLogonDC,
                 'AccountExpires' => $AccountExpires
               );

    }



  #######################
  ## $return = ConvertDateToEpoch( $date );
  ##    inverse of localtime();
  ##    $date   - string - format: mm/dd/yy[yy][ hh:mm:ss]
  ##    $return - the number of seconds since Jan 1, 1970 UTC
  ##    requires 'Time::Local' module
  ##
    sub ConvertDateToEpoch{
        my $self   = shift;
        my $inDate = shift;
                                                      #mn            #dy            #yr             #hr           #min          #sc            #part
        my( $a, $b, $c, $d, $e, $f, $g ) = $inDate=~/(\d{1,2})[\/\\\-](\d{1,2})[\/\\\-](\d{2,4})\s{0,1}(.{0,2}):{0,1}(.{0,2}):{0,1}(.{0,2})\s{0,1}([apmAPM]{0,2})/;
        $g = uc( $g );

        if( $d == 12 && $g eq 'AM' ){
            $d = 0;
        }elsif( $d == 12 && $g eq 'PM' ){
            $d = 12;
        }elsif( $g eq 'AM' ){
            $d = $d;
        }elsif( $g eq 'PM' ){
            $d = $d + 12;
        }

        return timegm($f,$e,$d,$b,$a,$c);
    }



  #######################
  ## $return = ConvertToEncodedSid( $sid );
  ##    $sid    - string - can be either hex value or 'S-1-x-xxx...' format.
  ##    $return - encoded hex format - e.g. '\50\20\a4...'
  ##      used for binding to object via the SID
  ##
    sub ConvertToEncodedSid{
        my $self = shift;
        my $str  = shift;

        my $cnt;
        my $tmp;
        my @tmp;

        if( $str eq '' ){
            $self->{ERR} = "Value can't be empty.";
            return 0;
        }

        $str = $self->ConvertSidStringToSid( $str ) if ( ($str=~s/\-/\-/gi) > 2 );      #if it has 3 or more dashes then will convert to hex since its most like in the S-1-xxx form

        @tmp = split(//,$str);

        $tmp = '\\';
        foreach ( @tmp ){
            $tmp = $tmp . unpack('H*',$_) . '\\';
        }

        chop $tmp;
        return $tmp;
    }



  #######################
  ## $return = ConvertDateToSQL( $indate );
  ##    $date - AD date reformatted to be pushed into SQL
  ##            expecting $indate to look like '5/21/2004 1:19:42 PM'
  ##
    sub ConvertDateToSQL{
        my $self   = shift;
        my $inDate = shift;

        my $DayPart;
        my $dy;
        my $Hour;
        my $mn;
        my $MinSec;
        my $yr;

        #$inDate = '5/21/2004 1:19:42 PM'; ## comes from AD like this

        $inDate=~/(\d\d?)\/(\d\d?)\/(\d{4})\s(\d\d?)(:\d\d?:\d\d?)\s(\w\w).*/;
        $mn    = $1;
        $mn    = '0' . $mn if length($mn) == 1;
        $dy    = $2;
        $dy    = '0' . $dy if length($dy) == 1;
        $yr    = $3;
        $Hour    = $4;
        $MinSec  = $5;
        $DayPart = uc $6;

        if( $Hour == 12 && $DayPart eq 'AM' ){
            return $yr . '-' . $mn . '-' . $dy . ' 00' . $MinSec;
        }elsif( $Hour == 12 && $DayPart eq 'PM' ){
            return $yr . '-' . $mn . '-' . $dy . ' ' . $Hour . $MinSec;
        }elsif( $DayPart eq 'AM' ){
            $Hour = '0' . $Hour if length($Hour) == 1;
            return $yr . '-' . $mn . '-' . $dy . ' ' . $Hour . $MinSec;
        }elsif( $DayPart eq 'PM' ){
            return $yr . '-' . $mn . '-' . $dy . ' ' . ($Hour + 12) . $MinSec;
        }
  }



  #######################
  ## $err = get_dcs( \@array[, OPTIONS] );
  ##    @array - array - array that will be populated with DC names
  ##    $err   - bit   - 1 for success; 0 for error; check $self->{ERR} for error message
  ##
  ##    OPTIONS is a list of key-value pairs
  ##      scope
  ##        current - only gather DCs on the current domain (default)
  ##        all     - gather all DCs in the forest (that can be seen in CN=Configuration)
  ##        root    - gather DCs from root domain
  ##      fqn
  ##        0       - gather just the server name - e.g. myserver (default)
  ##        1       - gather the fully qualified domain name of the server - e.g. myserver.domain.net
  ##
    sub get_dcs{
        my $self      = shift;
        my $array_ref = shift;
        my %options   = &$_import_options(@_);

        my %hash_ref;
        my $k;
        my $rec;
        my $res;

        ## default options
        $options{FQN}   = 0         if !exists $options{FQN};
        $options{SCOPE} = 'CURRENT' if !exists $options{SCOPE};

        my $res = $self->{LDAP}->search (
            base    => "CN=Sites,$self->{CONFIGURATION_LDAP}",
            scope   => 'subtree',
            filter  => '(objectclass=*)',
            attrs   => ['dNSHostName']
        );

        if ( ${$res}{errorMessage} ne '' ){
            $self->{ERR} = ${$res}{errorMessage};
            return 0;
        }

        my $rec = $res->as_struct;

        foreach ( keys %{$rec} ){

            my $server = uc( ${${$rec}{$_}}{dnshostname}[0] );

            if( $server ne '' ){

                if( uc($options{SCOPE}) eq 'ALL' ){

                    $server=~s/^([^\.]+)\..*/\1/ if( $options{FQN} != 1 );      # strip off domain name from fully qualified name
                    push @$array_ref,$server;

                }elsif( uc($options{SCOPE}) eq 'CURRENT' ){

                    if( $server=~/^[^\.]+\.$self->{DOMAIN_NAME}$/ ){
                        $server=~s/^([^\.]+)\..*/\1/ if( $options{FQN} != 1 );      # strip off domain name from fully qualified name
                        push @$array_ref,$server;
                    }

                }elsif( uc($options{SCOPE}) eq 'ROOT' ){

                    if( $server=~/^[^\.]+\.$self->{ROOT_DOMAIN_NAME}$/ ){
                        $server=~s/^([^\.]+)\..*/\1/ if( $options{FQN} != 1 );      # strip off domain name from fully qualified name
                        push @$array_ref,$server;
                    }

                }             # end if $options{SCOPE}

            }                 # end if $server ne ''

        }                     # end foreach keys %{$rec}

    }                         # end sub


  #######################
  ## @Details = GetAuthenAccount( $ServiceName | $AccountName, $PathOfConfigFile );
  ##    @Details     - array  - array containing the Account Name, Password, and Service Name that the account is designed for
  ##    $ServiceName - string - name of service to return details for (only $Servicename or AccountName needs to be supplied)
  ##    $AccountName - string - name of account to return details for (only $Servicename or AccountName needs to be supplied)
  ##    $PathOfConfigFile - string - this should be the full path to the config file where the account information is stored
  ##        Expecting the format of the Config File to be "AccountDN\tPassword\tServiceName\n"
  ##        Returns values for first instance of $ServiceName/$AccountName in the config file
  ##
    sub GetAuthenAccount{ 
        my $name = shift;
        my $path = shift;

        my $flgFirstLine = 0;
        my @return;

        if( ! -f $path ){
            die "'$path' file does not exist!\n";
        }

        open( FILE, $path );
        while( my $line=<FILE> ){

            if( $flgFirstLine == 0 ){

                $flgFirstLine = 1;   #sets flg on first loop

                if( $line!~/^AccountDN\tPassword\tServiceName/i ){

                    die "'$path' not formatted correctly!\n  Expecting: AccountDN\\\tPassword\\\tServiceName\\\n for first line.\n";

                }

            }else{

                if( $line=~/$name/i && $line!~/^\#/ ){

                    close FILE;
                    @return = split /\t/,$line;
                    return @return;

                }
            }
        }
        close FILE;
    }



  #####################
  ##  $err = GetMember( $DistinguishedName | samaccountname, \@ReturnedArray );
  ##    $DistinguishedName - string - fully qualified DN
  ##    \@ReturnedArray    - arrRef - will be filled with returned SamAccountNames
  ##    $err               - bit    - 1 for success; 0 for error; check $self->{ERR} for error message
  ##
    sub GetMember{
        my $self          = shift;
        my $DN            = shift;
        my $ReturnedArray = shift;

        my $arr_ref;
        my $res;
        my $rec;

        my @search_args;

        if( $DN=~/^CN\=/i && $DN=~/DC\=/i ){
            @search_args = (
                base    => $DN,
                scope   => 'base',
                filter  => '(objectClass=group)',
                attrs   => ['member']
            );
        }elsif( $DN ne '' ){
            @search_args = (
                base    => $self->{DOMAIN_NAME_LDAP},
                scope   => 'sub',
                filter  => "(samaccountname=$DN)",
                attrs   => ['member']
            );
        }else{
            $self->{ERR} = 'Group Name is not a valid group.';
            return 0;
        }

        ##lookup member list
        $res = $self->{LDAP}->search( @search_args );

        if ( ${$res}{errorMessage} ne '' ){
            $self->{ERR} = ${$res}{errorMessage};
            return 0;
        }

        $rec = $res->as_struct;

        foreach my $dn ( keys %{$rec} ){            #only one key, but need to 'loop' to grab it so that we have the proper upper case / lower case of string
            $arr_ref = ${${$rec}{$dn}}{member};
            last;
        }

        ##loop through member list and convert distinguished name to samaccountname
        foreach my $grp ( @{$arr_ref} ){

            $res = $self->{LDAP}->search(
                base    => $grp,
                scope   => 'base',
                filter  => '(objectClass=group)',
                attrs   => ['samaccountname']
            );

            $rec = $res->as_struct;

            foreach my $dn ( keys %{$rec} ){            #only one key, but need to 'loop' to grab it so that we have the proper upper case / lower case of string

                push @{$ReturnedArray}, ${${$rec}{$dn}}{samaccountname}[0];
                last;

            }    #end foreach my $dn

        }        #end foreach my $Grp

        return 1;
    }            #end sub



  #####################
  ##  $err = GetLocalMember( $groupname, $server, \@ReturnedArray );
  ##    $groupname      - string - samaccountname of local server group
  ##    $server         - string - server that $groupname is on
  ##    \@ReturnedArray - arrRef - will be filled with returned SamAccountNames
  ##    $err            - bit    - 1 for success; 0 for error; check $self->{ERR} for error message
  ##    REQUIRES SAMBA TO BE RUNNING!!!
  ##
    sub GetLocalMember{
        my $self          = shift;
        my $group         = shift;
        my $server        = shift;
        my $ReturnedArray = shift;

        my $exe;
        my $file          = $self->{ACCOUNTS_FILE};
        my $pw;
        my $res;
        my $user;

        if( $self->{SAMBA} != 1 ){

            ## first time, thus have to check to see if samba is running
            open(EXE, "ps -Csmbd|");
            while( my $line=<EXE> ){
                if( $line=~/\ssmbd/i ){
                    $self->{SAMBA} = 1;
                    last;
                }
            }
            close EXE;

            if( $self->{SAMBA} != 1 ){
                $self->{ERR} = 'Samba not running! "smbd" process not detected!';
                return 0;
            }

        }

        ( $user, $pw ) = GetAuthenAccount( 'LDAP', $self->{ACCOUNTS_FILE} );

        ##translate username from distinguished name to samaccountname if its a distinguisedname
        if( $user=~/^CN=/i ){
            $res = $self->{LDAP}->search(
                base    => $user,
                scope   => 'base',
                filter  => '(objectClass=user)',
                attrs   => ['samaccountname']
            );

            $res = $res->as_struct;

            foreach my $dn ( keys %{$res} ){            #only one key, but need to 'loop' to grab it so that we have the proper upper case / lower case of string
                $user =  ${${$res}{$dn}}{samaccountname}[0];
                last;
            }
        }

        $exe = "net rpc group members \"$group\" -U$user%$pw -S$server";

        open(EXE,"$exe|");
        while( my $line=<EXE> ){
            chomp $line;
            push @{$ReturnedArray},$line;
        }
        close EXE;

        return 1;

    }



  #####################
  ##  $err = GetLocalObjects( $server, \%ReturnedHash );
  ##    $server        - string  - server that $groupname is on
  ##    \%ReturnedHash - hashRef - Keys   - will be the samaccountname of all the local users and local groups on the box
  ##                               Values - array; 
  ##                                 element 0 - samaccountname
  ##                                 element 1 - object type: user or group
  ##                                 element 2 - description
  ##    $err           - bit     - 1 for success; 0 for error; check $self->{ERR} for error message
  ##    REQUIRES SAMBA TO BE RUNNING!!!
  ##
    sub GetLocalObjects{
        my $self         = shift;
        my $server       = shift;
        my $ReturnedHash = shift;

        my $colWidth;
        my $exe;
        my $file         = $self->{ACCOUNTS_FILE};
        my $flgFirstLine;
        my $pw;
        my $res;
        my $user;

        my %tmp;

        if( $self->{SAMBA} != 1 ){

            ## first time, thus have to check to see if samba is running
            open(EXE, "ps -Csmbd|");
            while( my $line=<EXE> ){
                if( $line=~/\ssmbd/i ){
                    $self->{SAMBA} = 1;
                    last;
                }
            }
            close EXE;

            if( $self->{SAMBA} != 1 ){
                $self->{ERR} = 'Samba not running! "smbd" process not detected!';
                return 0;
            }

        }

        ( $user, $pw ) = GetAuthenAccount( 'LDAP', $self->{ACCOUNTS_FILE} );

        ##translate username from distinguished name to samaccountname if its a distinguisedname
        if( $user=~/^CN=/i ){
            $res = $self->{LDAP}->search(
                base    => $user,
                scope   => 'base',
                filter  => '(objectClass=user)',
                attrs   => ['samaccountname']
            );

            $res = $res->as_struct;

            foreach my $dn ( keys %{$res} ){            #only one key, but need to 'loop' to grab it so that we have the proper upper case / lower case of string
                $user =  ${${$res}{$dn}}{samaccountname}[0];
                last;
            }
        }

        #gather local users accounts
        $exe = "net rpc user -U$user%$pw -S$server -l";

        open(EXE,"$exe|");
        while( my $line=<EXE> ){
            my $comment;
            my $user;
        
            chomp $line;
            next if $line eq '';
            if( $flgFirstLine != 1 ){
                $line=~/^(user.*)comment.*/i;
                $colWidth = length($1) - 1;
                $flgFirstLine = 1 if $colWidth ne '';
                next;
            }

            #split user name from comment
            $line=~/(.{$colWidth})\s(.*)/;
            $user    = $1;
            $comment = $2;
            #remove trailing spaces
            $user=~s/\s+$//;
            ${$ReturnedHash}{$user} = [$user,'user',$comment];
        }
        close EXE;
        undef $flgFirstLine;
        undef $colWidth;

        #gather local groups
        #first just get the local group descriptions; we'll have to come back for their unchopped names
        $exe = "net rpc group -U$user%$pw -S$server -l";

        open(EXE,"$exe|");
        while( my $line=<EXE> ){
            my $comment;
            my $group;

            chomp $line;
            next if $line eq '';
            if( $flgFirstLine != 1 ){
                $line=~/^(group.*)comment.*/i;
                $colWidth = length($1) - 1;
                $flgFirstLine = 1 if $colWidth ne '';
                next;
            }

            #split group name from comment
            $line=~/(.{$colWidth})\s(.*)/;
            $group   = $1;
            $comment = $2;
            #remove trailing spaces
            $group=~s/\s+$//;
            $tmp{$group} = $comment;
        }
        close EXE;

        #now gather unchopped group name
        $exe = "net rpc group -U$user%$pw -S$server";

        open(EXE,"$exe|");
        while( my $line=<EXE> ){

            chomp $line;
            $line=~s/\s+$//;
            next if $line eq '';

            #if the previously fetched group name appears inside the current unchopped name, they're most likely the same group and will go ahead and make a substition
            #need to do this because net rpc returns the names chopped to 21 chars long in order to fit the group description on the screen when using the "-l" option
            foreach my $key ( keys %tmp ){
                if( $line=~/$key/ ){
                    ${$ReturnedHash}{$line} = [ $line, 'group', $tmp{$key} ];
                }
            }

        }
        close EXE;

        return 1;

    }


  #####################
  ##  $fqn = $obj->get_fqn( $server );
  ##     $server - string - server that you want the fully qualified name for - e.g. myserver
  ##     $fqn    - string - fully qualified name of $server - e.g. myserver.mydomain.net
  ##
    sub get_fqn{
        my $self   = shift;

        ($_) = gethostbyname($_[0]);

        return $_;
    }



  #############################################################################
  #
  # ConvertSidToStringSid and ConvertStringSidToSid are taken from  
  #   Win32::Security::SID,  Author: Toby Ovod-Everett
  #
  #############################################################################

  #######################
  ## $SidString = ConvertSidToSidString( $rawSid );
  ##   $rawsid    - hex    - this is the sid in its raw form straight from the AD object
  ##   $SidString - string - converted to the form S-1-xxx....
  ##
    sub ConvertSidToSidString{
        my $self = shift;
	    my $sid  = shift;

        $sid or return;
        my($Revision, $SubAuthorityCount, $IdentifierAuthority0, $IdentifierAuthorities12, @SubAuthorities) = unpack("CCnNV*", $sid);
        my $IdentifierAuthority = $IdentifierAuthority0 ? sprintf('0x%04hX%08X', $IdentifierAuthority0, $IdentifierAuthorities12) : $IdentifierAuthorities12;
        $SubAuthorityCount == scalar(@SubAuthorities) or return;
        return "S-$Revision-$IdentifierAuthority-".join("-", @SubAuthorities);
    }



  #######################
  ## $rawSid = ConvertSidStringToSid( $SidString );
  ##   $SidString - string - converted to the form S-1-xxx....
  ##   $rawsid    - hex    - this is the sid in its raw form straight from the AD object
  ##
    sub ConvertSidStringToSid {
	    my $self = shift;
	    my $text = shift;

        my(@Values) = split(/\-/, $text);
        (shift(@Values) eq 'S' && scalar(@Values) >= 3) or return;
        my $Revision = shift(@Values);
        my $IdentifierAuthority = shift(@Values);
        if (substr($IdentifierAuthority, 0, 2) eq '0x') {
            $IdentifierAuthority = pack("H12", substr($IdentifierAuthority, 2));
        } else {
            $IdentifierAuthority = pack("nN", 0, $IdentifierAuthority);
        }
        return pack("CCa6V*", $Revision, scalar(@Values), $IdentifierAuthority, @Values);
    }
  ############################################################################


DESTROY {
    my $self = shift;

    $self->unbind();
    $self->{PING}->close();

}
 

  
1;

__END__
