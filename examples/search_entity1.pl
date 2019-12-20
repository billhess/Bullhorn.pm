#----------------------------------------------------------------------
#
# Example of Searching for Candidate Entities in Bullhorn
# Uses a query of when the record was Added or Last Modified
#
# See code below - one of the lines to assign $query is commented
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


print "\nGET AUTHORIZATION CODE\n";
if( $bh->get_auth_code ) {
   $bh->dump_error;
   $bh->dump_debug;
   exit 1;
} 


print "\nGET ACCESS TOKEN\n";
if( $bh->get_access_token ) {
   $bh->dump_error;
   $bh->dump_debug;
   exit 1;
}


print "\nLOGIN\n";
if( $bh->login ) {
   $bh->dump_error;
   $bh->dump_debug;
   exit 1;
}



print "\nSEARCH CANDIDATE\n";


# Get time range from 1 day ago to now
my $t2 = $bh->ts_epoch_now;
my $t1 = $t2 - (1 * 24 * 60 * 60 * 1000);

# Bullhorn likes certain time formats in its query 
my $d1 = $bh->ts_epoch_to_lucene($t1);
my $d2 = $bh->ts_epoch_to_lucene($t2);

print "T1 = $t1   $d1\n";
print "T2 = $t2   $d2\n";

#my $query = qq(dateAdded:[$d1 TO $d2]);
my $query = qq(dateLastModified:[$d1 TO $d2]);

#my $fields = "*";
my $fields =
    "id,firstName,lastName,owner," .
    "email,email2,email3,phone,phone2,phone3," .
    "dateAdded,userDateAdded,dateLastModified,dateLastComment";

my $i = 0;
my $s = {};

# Get 50 records at a time and then ask for more if needed
my $start = 0;
my $count = 50;

do {

   $s = $bh->search_entity( "Candidate", $query, $fields,
                            "id", $count, $start );

   print "\nCANDIDATE COUNT = " . scalar @{$s->{data}} . "\n\n";

   #if($s) {
   #   print Dumper($s) , "\n\n";
   #}
   
   foreach my $c ( @{$s->{data}} ) {
      print "$i: " . $c->{firstName} . " " . $c->{lastName} . "\n";
      print "\t" . $bh->ts_epoch_to_mysql($c->{dateAdded})  . "\n";
      print "\t" . $bh->ts_epoch_to_mysql($c->{dateLastModified})  . "\n";
      $i++;
   }

   $start = $s->{start} + $count;
      
} while ($s->{start} + $s->{count}) < $s->{total};



print "\n\n\nDEBUG\n";
$bh->dump_debug;

print "\n\n\nERROR\n";
$bh->dump_error;

