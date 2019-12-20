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
   user_id       => "",
   user_pw       => "",
   client_id     => "",
   client_secret => "",
};


$creds_soap = { 
   username      => "",
   password      => "",
   apiKey        => "",
};






#======================================================================
# END OF BullhornAuth.pm
#======================================================================
1;
