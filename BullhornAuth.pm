#======================================================================
#
# NAME:  BullhornAuth.pm
#
# DESC:  
#
# ARGS:  
#
# RET:   
#
# HIST:  
#
#======================================================================
package BullhornAuth;

use strict;


use vars qw($creds_rest $creds_soap);

$creds_rest = { 
   user_id       => "acme.restapi",
   user_pw       => "AcmePW123",
   client_id     => "",
   client_secret => "",
   oauth_url     => "https://auth-west.bullhornstaffing.com/oauth",
   rest_url      => "https://rest-west.bullhornstaffing.com/rest-services",
};


$creds_soap = { 
   username      => "apiuser.acme",
   password      => "AcmePW456",
   apiKey        => "",
};






#======================================================================
# END OF BullhornAuth.pm
#======================================================================
1;
