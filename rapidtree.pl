#!/usr/bin/perl
#
# Lawrence Billson, 2015
#
# Interpret a UNIX 'script' file which contains the output of a few Cisco commands, generate a physical tree of what's
# connected, where and how
#
# To use, log your session, then login to the switches / routers on the network
# from there, run the following commands on them all - then run this program against your capture
# 
# Run these commands:
#	show ip arp
# 	show mac address-table
#	show int status
#
# You will need to download the OpenWRT style mac-to-devinfo files, or install the package. Files should be in these locations
#
$macfiles[0] = '/var/cache/mac-to-devinfo/iab.txt';
$macfiles[1] = '/var/cache/mac-to-devinfo/oui.txt';
#

# Do we want tree mode, or csv mode? Change the mode to zero for a csv output
$treemode = 0; 

# Little subroutine to convert a Cisco style MAC into a more useful thing
sub ciscomac {
        $inmac = $_[0];
        # remove the full stops
        $inmac =~ s/\.//g;
        # Add the colons
        $omac = join(':', unpack '(A2)*', $inmac);
        return $omac;
        }


sub lookup {
	$inmac = $_[0];
	# Turn it into uppercase
	$inmac =~ tr/a-z/A-Z/;
	# Split it into parts
	@macparts = split(':',$inmac);
	$retval =  $macvendor{"$macparts[0]-$macparts[1]-$macparts[2]"};
	#print "Lookup input $inmac - output is $macparts[0] $macparts[1] $macparts[2] - return $retval\n";
	}


# Work begins here



# If we're not in tree mode, print out a csv headder
if (!$treemode) {
	print "\"Host\",\"Interface\",\"Media Type\",\"VLAN\",\"Description\",\"MAC Address\",\"IP\",\"MAC Vendor code\"\n";
	}

                                                                            
foreach $macfile (@macfiles) {                                              
        open(FILE,$macfile);                                                
        while ($line = <FILE>) {                                                                 
                @lparts = split(' ',$line);                                 
                if ($lparts[1] eq '(hex)') {                                
                        chomp($line);                                       
                        # This value is useful to us, store it in a big hash
                        #                                    
                        # 0 = 00-00-00                       
                        # 1 = (hex)                                                              
                        # 2-> = Vendor name                  
                        @vendorname = split('\t',$line);     
                                                                                                            
                        $macvendor{$lparts[0]} = $vendorname[2];
                        }
                }                                                                                    
        close(FILE);                                                                               
        }                                   


# Open the input file
open(ARPIN,"$ARGV[0]");

# Cycle through the file, try and find ARP entries, jam them into a hash table to use for lookups
while ($line = <ARPIN>) {
	chomp($line);
	@lparts = split(' ',$line);

	# See if we can't work out the current hostname
	if ($line =~ /show mac address-table/) {
		# We've found the switch where the cam table was dumped, let's learn its hostname
		($hostname,$junk) = split('\#',$lparts[0]);
		#
		# We'll leave hostname as our variable until it gets overwritten (by another CAM table dump)
		}

	# If column 2 looks like a MAC address and column 3 says DYNAMIC, we've got a CAM table entry
	if (($lparts[2] eq "DYNAMIC") && ($lparts[1] =~ /[0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4}/)) {
		$thisinterface = $lparts[3];
		$thismac = $lparts[1];
		# Store it - 
		# 
		# Is there an existing entry under that switch or port
		if ($cam{$hostname}{$thisinterface}[0]) {
			# We're not the first, we can simply push something onto the array
			push @{ $cam{$hostname}{$thisinterface} }, $thismac;
			}
		else {
			$cam{$hostname}{$thisinterface}[0] = $thismac;
			}

		}


	# If column 4 says ARPA and column 3 contains a MAC address, we've got a live one
	if (($lparts[4] eq "ARPA") && ($lparts[3] =~ /[0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4}/)) {
		$thisip = $lparts[1];
		$thismac = $lparts[3];
		$ip{$thismac} = $thisip;
		}
	}
close(ARPIN);

# Some test code - probably need to delete it!
# See if we can dump the mac address stuff
#foreach $item (sort keys %cam){
#	print "$item: \n";
#  	foreach $iteminitem (sort keys %{$cam{$item}}){
#    		print "\t$iteminitem\n";
#		foreach $macad ( @{ $cam{$item}{$iteminitem} }) {
#			print "\t\t$macad\n";
#			}
#  		}
#	}

# Read through the files again, this time we're looking for a show interface status line - we can expand on that output with what we know already

# Open the input file
open(DISPLAY,"$ARGV[0]");

# Cycle through the file, try and find ARP entries, jam them into a hash table to use for lookups
while ($line = <DISPLAY>) {

	# Clear out stale descriptions
	$description = "";

	chomp($line);
	@lparts = split(' ',$line);

	if (($incmd) && ($line =~ $hostname)) {
		$incmd = 0;
		}

	if (($line =~ /show/) && ($line =~ /int/) && ($line =~ /status/))  {
		# Show int status line?
		($hostname,$junk) = split('\#',$lparts[0]);
		if ($treemode) {
			print "$hostname\n";
			}
		$incmd = 1;
		}

	# Are we in a status line ?
	if (($incmd) && ($lparts[5]) && (!($line =~ /Duplex/)))  {
		# We're getting lines of show interface status now
		#
		$sport = $lparts[0];
		# damn you Cisco, you make it hard, the description may or may not be there, we need to do some processing
		if ($lparts[1] =~ /connected|notconnect/) {
			# The port has no description
			$media = $lparts[5];
			$vlan = $lparts[2];
			}
		
		else {
			# The port has a description, let's figure out what it is
			@desc = split(/connected|notconnect/,$line);
			
			$description = $desc[0];
			$description =~ s/^\S+\s*//;

			# Remove some whitespace at the end
			$description=~s/\s+$//;

			@dmedia = split(' ',$desc[1]);
			$media = $dmedia[3];
			$vlan = $dmedia[0];
			}

		# Make it clear about the not installed ones
		$media =~ s/Not/Not Installed/;




		# We've got enough information!
	
		# Deliberate decision - we only care about stuff that has a MAC address behind it
		
		if ($cam{$hostname}{$sport}[0]) {
			#  In tree mode - print it out like a tree eh!

			if ($treemode) {
				print "\t$sport ($media) VLAN:$vlan $description\n";
               			foreach $macad ( @{ $cam{$hostname}{$sport} }) {
					# Lookup the IP address
					$myip = $ip{$macad};				
                       			print "\t\t$macad\t$myip\t";
					
					# Time to get serious - let's turn the MAC address into something useful
	
					$trymac = ciscomac($macad);
					$ven = lookup($trymac);
				
	
					print $ven;
					print "\n";
       	                		}

				}	
			else {
				# Print out some CSV stuff - formatted like
				#"Host","Interface","Media Type","VLAN","Description","MAC Address","IP","MAC Vendor code"

                                foreach $macad ( @{ $cam{$hostname}{$sport} }) {
                                        $myip = $ip{$macad};
                                        $trymac = ciscomac($macad);
                                        $ven = lookup($trymac);
					print "\"$hostname\",\"$sport\",\"$media\",\"$vlan\",\"$description\",\"$macad\",\"$myip\",\"$ven\"\n";
                                        }
				}

			}

		}	


	}


