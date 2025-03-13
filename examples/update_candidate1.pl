#----------------------------------------------------------------------
#
# Example of Updating a Candidate Entity in Bullhorn
# Searches for a Candidate by ID and then updates the phone number
# Pass the ID in as the only argument on the command line
#
#  USAGE:   $ perl update_candidate1.pl 123456
#
# Use Data::Dumper to see the raw JSON/Perl hash returned
# This is a great way to learn/debug and see what is possible
#
#----------------------------------------------------------------------
use strict;

use Data::Dumper;

use Bullhorn;
use BullhornAuth;

my $rc;

my $bh = Bullhorn->new( $BullhornAuth::creds_rest );

$bh->{debug} = 1;


print "\nCONNECT TO BULLHORN\n";

if( $bh->connect ) {
   $bh->dump_error;
   $bh->dump_debug;
   exit 1;
} 


# DECLARE FIELDS - NOT VERY EFFICIENT TO JUST USE "*"
#my $fields = "*";
my $fields =
    "id,firstName,lastName,owner," .
    "email,email2,email3,phone,phone2,phone3," .
    "dateAdded,userDateAdded,dateLastModified,dateLastComment";


my $id = $ARGV[0];


print "\nSEARCH CANDIDATE\n";

my $cand = $bh->search_entity_id( "Candidate", $id, $fields );

my $c;
if( exists $cand->{data} ) {
   $c = $cand->{data}[0];
}
else {
   print "CANDIDATE NOT FOUND - $id\n";
   exit 1;
}

#print Dumper($c) , "\n\n\n";
#$bh->dump_debug;

print $c->{firstName} . " " . $c->{lastName} . "\n";
print "\t" . $c->{email}  . "\n";
print "\t" . $c->{phone}  . "\n";
print "\t" . $bh->ts_epoch_to_mysql($c->{dateAdded})  . "\n";
print "\t" . $bh->ts_epoch_to_mysql($c->{dateLastModified})  . "\n";



print "\nUPDATE CANDIDATE\n";

my $phone = "123-867-5309";
$phone = "123-555-1212" if $c->{phone} eq "123-867-5309";

# DEFINE A HASHREF FOR THE UPDATE
my $uc = { phone => $phone };

my $u = $bh->update_entity( "Candidate", $id, $uc );

#print Dumper($u) , "\n\n\n";



print "\nCHECK CANDIDATE\n";

my $cand = $bh->search_entity_id( "Candidate", $id, $fields );

my $c;
if( exists $cand->{data} ) {
   $c = $cand->{data}[0];
}
else {
   print "CANDIDATE NOT FOUND - $id\n";
   exit 1;
}

print $c->{firstName} . " " . $c->{lastName} . "\n";
print "\t" . $c->{phone}  . "\n";

