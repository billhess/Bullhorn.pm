#======================================================================
#
# NAME:  Bullhorn.pm
#
# DESC:  Bullhorn REST API
#
# ARGS:  
#
# RET:   
#
# HIST:  
#
#======================================================================
# Copyright 2016 - Technology Resource Group LLC as an unpublished work
#======================================================================
package Bullhorn;

use strict;

use Data::Dumper;
use Encode;
use File::Basename;
use HTTP::Request::Common qw(GET POST PUT);
use JSON;
use LWP::UserAgent;
use MIME::Base64;
use Time::Local;
use URI::Escape;



#----------------------------------------------------------------------
#
# NAME:  new
#
# DESC:  Create a new Bullhorn object
#
# ARGS:  $h1 - 'Bullhorn'
#        $h2 - undef|HASH
#
# RETN:  Bullhorn object
#
# HIST:  
#
#----------------------------------------------------------------------
sub new {
   my ($h1, $h2) = @_;

   my $h = undef;
   
   #------------------------------------------------------------
   # class name - Bullhorn->new();
   #------------------------------------------------------------
   if($h1 eq 'Bullhorn') {
      $h = $h2 if ref $h2 eq 'HASH';
   }
   else {
      print STDERR 
          "Bullhorn::new ",
          "ERROR: Invalid argument passed\n";
      return undef; 
   }
   

   #------------------------------------------------------------
   # Define Bullhorn Object structure
   #------------------------------------------------------------
   my $d = { user_id        => '',
             user_pw        => '',
             client_id      => '',
             client_secret  => '',
             http_timeout   => 30,
             http_proxy     => '',
             https_proxy    => '',
             auth_code      => '',
             access_href    => { },
             access_ts      => 0,
             login_href     => { },
             retry_wait     => 20,
             retry_max      => 10,
             debug          => 0,
             debug_http     => 0,
             debug_log      => [ ],
             error_log      => [ ]  };

   
   #------------------------------------------------------------
   # Enforce Bullhorn structure
   # Copy each field if it exists with same ref type
   #------------------------------------------------------------
   foreach (keys %$d) {
      if( exists $h->{$_} && (ref $h->{$_} eq ref $d->{$_}) ) {
         $d->{$_} = $h->{$_};
      }
   }


   #------------------------------------------------------------
   # JSON object
   #------------------------------------------------------------   
   my $json = JSON->new->allow_nonref;

   $d->{json} = $json;


   #------------------------------------------------------------
   # LWP Object
   #------------------------------------------------------------   
   my $ua = new LWP::UserAgent;

   $ua->timeout( $d->{http_timeout} );

   #$ua->proxy( 'http',  $d->{http_proxy} )   if $d->{http_proxy}   ne "";
   #$ua->proxy( 'https', $d->{https_proxy} )  if $d->{https_proxy}  ne "";

   #$req->proxy_authorization_basic("ahessbi", "");
   
   #$ENV{HTTP_PROXY}               = $d->{http_proxy};
   #$ENV{HTTP_PROXY_USERNAME}      = '';
   #$ENV{HTTP_PROXY_PASSWORD}      = '';
   #$ENV{HTTPS_PROXY}               = $d->{https_proxy};
   #$ENV{HTTPS_PROXY_USERNAME}      = '';
   #$ENV{HTTPS_PROXY_PASSWORD}      = '';

   
   $d->{ua} = $ua;
   
   
   
   return bless $d, 'Bullhorn';
}


#----------------------------------------------------------------------
#
# NAME:  error log
#
# DESC:  
#
# ARGS:  
#
# RETN:  
#
# HIST:  
#
#----------------------------------------------------------------------
sub add_error {
   my ($self, $msg) = @_;

   push @{$self->{error_log}}, $msg;
}


sub dump_error {
   my ($self) = @_;

   my $lastmeth;
   foreach ( @{$self->{error_log}} ) {
      my ($thismeth) = split /\:/, $_;
      print "\n\n" if $thismeth ne $lastmeth;
      $lastmeth = $thismeth;

      print "$_\n";
   }
}




#----------------------------------------------------------------------
#
# NAME:  debug log
#
# DESC:  
#
# ARGS:  
#        
# RETN:  
#
# HIST:  
#
#----------------------------------------------------------------------
sub add_debug {
   my ($self, $msg) = @_;

   push @{$self->{debug_log}}, $msg;
}

sub dump_debug {
   my ($self) = @_;

   my $lastmeth;
   foreach ( @{$self->{debug_log}} ) {
      my ($thismeth) = split /\:/, $_;
      print "\n\n" if $thismeth ne $lastmeth;
      $lastmeth = $thismeth;

      print "$_\n";
   }
}





#----------------------------------------------------------------------
#
# NAME:  get_auth_code
#
# DESC:  Get Authorization Code for BH REST API
#
# https://auth.bullhornstaffing.com/oauth/authorize?
#    client_id=<CLIENT ID>
#    response_type=code
#    username=<USER ID>
#    password=<PASSWORD>
#    action=Login
#
# Calling this should redirect back to www.techrg.com since that
# is the address we gave BH during setup of the API user.
# So we need to check the previous header to get 'Location'
# and get the auth code from the query string where param = 'code'
#
#
# ARGS:  
#
# RETN:  0 - Success
#        1 - Error   Check $self->{error_log}
#
# HIST:  
#
#----------------------------------------------------------------------
sub get_auth_code {
   my ($self) = @_;

   if( $self->{client_id} eq "") {
      $self->add_error("get_auth_code: client_id not defined");
      return 1;
   }

   if( $self->{user_id} eq "") {
      $self->add_error("get_auth_code: user_id not defined");
      return 1;
   }

   if( $self->{user_pw} eq "") {
      $self->add_error("get_auth_code: user_pw not defined");
      return 1;
   }

   
   my $url = 
       qq(https://auth.bullhornstaffing.com/oauth/authorize) . "?" .
       qq(client_id=) . $self->{client_id} . "&" . 
       qq(response_type=code)              . "&" .
       qq(username=) . $self->{user_id}    . "&" .
       qq(password=) . $self->{user_pw}    . "&" . 
       qq(action=Login);

   $self->add_debug("get_auth_code: URL = $url" . "\n") if $self->{debug_http};
   
   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("get_auth_code: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
   
      my $res = $self->{ua}->request($req);

      $self->add_debug("get_auth_code: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};

      if($res->is_success) {
         my $redirect_url = $res->previous->header('Location');

         $self->add_debug("get_auth_code: LOC = $redirect_url")
             if $self->{debug_http};
      
         if( $redirect_url =~ /code=(.*)\&/ ) {
            $self->{auth_code} = $1;
         }

         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("get_auth_code: successful on try $tries");
         }
      }
      else {
         $self->add_error("get_auth_code: HTTP call failed");
         $self->add_error("get_auth_code: ". $res->status_line);
         $self->add_error("get_auth_code: try = $tries");

         # If we don't already have this info in the debug log
         # add it to the error log
         if(! $self->{debug_http}) {
            $self->add_error("get_auth_code: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("get_auth_code: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }

         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};
      }
   }

   
   
   if( $self->{auth_code} eq "" ) {
      $self->add_error("get_auth_code: Did not get auth code");
      return 1;
   }
   

   return 0;
}




#----------------------------------------------------------------------
#
# NAME:  get_access_token
#
# DESC:  Get Access Token for BH REST API
#
# https://auth.bullhornstaffing.com/oauth/token?
#    grant_type=authorization_code
#    code=<AUTH CODE>
#    client_id=<CLIENT ID>
#    client_secret=<CLIENT SECRET>
#
#
# Calling this returns JSON like this
#
# {  
#     "access_token"  : "5:a6477004-77ff-4d99-a7e8-91105a6a4baa",
#     "token_type"    : "Bearer",
#     "expires_in"    : 600,
#     "refresh_token" : "5:3daca6ce-6d12-4db5-b6d3-8da8a7a27b08"
#  }  
#
#
# ARGS:  
#
# RETN:  0 - Success
#        1 - Error   Check $self->{error_log}
#
# HIST:  
#
#----------------------------------------------------------------------
sub get_access_token {
   my ($self) = @_;

   if( $self->{client_id} eq "") {
      $self->add_error("get_access_token: client_id not defined");
      return 1;
   }

   if( $self->{client_secret} eq "") {
      $self->add_error("get_access_token: client_secret not defined");
      return 1;
   }
   
   if( $self->{auth_code} eq "") {
      $self->add_error("get_access_token: auth_code not defined");
      return 1;
   }


   # Initialize the timestamp for getting the access token
   $self->{access_ts} = 0;


   my $url = 
       qq(https://auth.bullhornstaffing.com/oauth/token) . "?" .
       qq(grant_type=authorization_code)                 . "&" .
       qq(code=) . $self->{auth_code}                    . "&" . 
       qq(client_id=) . $self->{client_id}               . "&" .
       qq(client_secret=) . $self->{client_secret};

   $self->add_debug("get_access_token: URL = $url" . "\n")
       if $self->{debug_http};
   
   my $req = HTTP::Request->new(POST => $url);

   $self->add_debug("get_access_token: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);

      $self->add_debug("get_access_token: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
   
      my $access_href_json;
   
      if($res->is_success) {
         $access_href_json = $res->content;
         
         $self->add_debug("get_access_token: $access_href_json")
             if $self->{debug_http};
         
         $self->{access_href} = $self->{json}->decode($access_href_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("get_access_token: successful on try $tries");
         }
      }
      else {
         $self->add_error("get_access_token: HTTP call failed");
         $self->add_error("get_access_token: ". $res->status_line);
         $self->add_error("get_access_token: try = $tries");

         # If we don't already have this info in the debug log
         # add it to the error log
         if(! $self->{debug_http}) {
            $self->add_error("get_access_token: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("get_access_token: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }
      
         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};
      }
   }
   


   if( (! exists $self->{access_href}->{access_token} ) ||
       ($self->{access_href}->{access_token} eq "")  ) {
      $self->add_error("get_access_token: Did not get access_token");
      return 1;
   }


   # Set the time when we got the access token so we 
   # know when to refresh later
   $self->{access_ts} = time;

   
   return 0;
}




#----------------------------------------------------------------------
#
# NAME:  refresh_access_token
#
# DESC:  Refresh Access Token for BH REST API
#
# https://auth.bullhornstaffing.com/oauth/token?
#    grant_type=refresh_token
#    refresh_token=<REFRESH TOKEN>
#    client_id=<CLIENT ID>
#    client_secret=<CLIENT SECRET>
#
#
# Calling this returns JSON like this
#
# {  
#     "access_token"  : "5:a6477004-77ff-4d99-a7e8-91105a6a4baa",
#     "token_type"    : "Bearer",
#     "expires_in"    : 600,
#     "refresh_token" : "5:3daca6ce-6d12-4db5-b6d3-8da8a7a27b08"
#  }  
#
#
# ARGS:  
#
# RETN:  0 - Success
#        1 - Error   Check $self->{error_log}
#
# HIST:  
#
#----------------------------------------------------------------------
sub refresh_access_token {
   my ($self) = @_;

   if( $self->{client_id} eq "") {
      $self->add_error("refresh_access_token: client_id not defined");
      return 1;
   }

   if( $self->{client_secret} eq "") {
      $self->add_error("refresh_access_token: client_secret not defined");
      return 1;
   }
   
   if( $self->{access_href}->{refresh_token} eq "") {
      $self->add_error("refresh_access_token: refresh_token not defined");
      return 1;
   }


   # Initialize the timestamp for getting the access token
   $self->{access_ts} = 0;


   my $url = 
       qq(https://auth.bullhornstaffing.com/oauth/token)          . "?" .
       qq(grant_type=refresh_token)                               . "&" .
       qq(refresh_token=) . $self->{access_href}->{refresh_token} . "&" . 
       qq(client_id=) . $self->{client_id}                        . "&" .
       qq(client_secret=) . $self->{client_secret};

   $self->add_debug("refresh_access_token: URL = $url" . "\n")
       if $self->{debug_http};
   
   my $req = HTTP::Request->new(POST => $url);

   $self->add_debug("refresh_access_token: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
   
      my $res = $self->{ua}->request($req);
   
      if($res->is_success) {
         my $access_href_json = $res->content;
         
         $self->add_debug("refresh_access_token: $access_href_json")
             if $self->{debug_http};
         
         $self->{access_href} = $self->{json}->decode($access_href_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("refresh_access_token: successful on try $tries");
         }
      }
      else {
         $self->add_error("refresh_access_token: HTTP call failed");
         $self->add_error("refresh_access_token: ". $res->status_line);
         $self->add_error("refresh_access_token: try = $tries");

         # If we don't already have this info in the debug log
         # add it to the error log
         if(! $self->{debug_http}) {
            $self->add_error("refresh_access_token: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("refresh_access_token: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }
      
         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};
      }
   }

   
   if( (! exists $self->{access_href}->{access_token} ) ||
       ($self->{access_href}->{access_token} eq "")  ) {
      $self->add_error("refresh_access_token: Did not refresh access_token");
      return 1;
   }


   # Set the time when we got the access token so we 
   # know when to refresh later
   $self->{access_ts} = time;

   
   return 0;
}




#----------------------------------------------------------------------
#
# NAME:  check_access_token
#
# DESC:  Check the access token to see if it needs a refresh
#
# ARGS:  
#
# RETN:  0 - Success
#        1 - Error   Check $self->{error_log}
#
# HIST:  
#
#----------------------------------------------------------------------
sub check_access_token {
   my ($self) = @_;

   # Determine how long we have been using the current token
   # Add 20 seconds 
   my $d = time - $self->{access_ts};

   $self->add_debug("check_access_token: time diff = $d")
       if $self->{debug_http};
   
   my $rc = 0;

   if( $d > ($self->{access_href}->{expires_in} - 20) ) {
      $rc = $self->refresh_access_token;      
      $self->add_debug("check_access_token: refresh token - RET = $rc");      
   }
       
   return $rc;
}





#----------------------------------------------------------------------
#
# NAME:  login
#
# DESC:  Login to the BH REST API
#
# https://rest.bullhornstaffing.com/rest-services/login?
#    version=*
#    access_token=<ACCESS TOKEN>
#
#
# Calling this returns JSON like this
#
# {
#    "BhRestToken" : "8b92f340-5efe-4bfd-9c47-479f2cf3ea52",
#    "restUrl" : "https://rest5.bullhornstaffing.com/rest-services/1zsyw4/"
#  }
#
#
# ARGS:  
#
# RETN:  0 - Success
#        1 - Error   Check $self->{error_log}
#
# HIST:  
#
#----------------------------------------------------------------------
sub login {
   my ($self) = @_;

   if( $self->{access_href}->{access_token} eq "") {
      $self->add_error("login: access_token not defined");
      return 1;
   }


   my $url = 
       qq(https://rest.bullhornstaffing.com/rest-services/login) . "?" .
       qq(version=*) . "&" .
       qq(access_token=) . $self->{access_href}->{access_token};

   $self->add_debug("login: URL = $url" . "\n");
   
   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("login: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
   
      my $res = $self->{ua}->request($req);

      $self->add_debug("login: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $login_json = $res->content;
         
         $self->add_debug("login: $login_json");
         
         $self->{login_href} = $self->{json}->decode($login_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("login: successful on try $tries");
         }
      }
      else {
         $self->add_error("login: HTTP call failed");
         $self->add_error("login: " . $res->status_line);
         $self->add_error("login: try = $tries");

         # If we don't already have this info in the debug log
         # add it to the error log
         if(! $self->{debug_http}) {
            $self->add_error("login: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("login: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }
      
         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};
      }
   }
   

   
   if( (! exists $self->{login_href}->{restUrl} ) ||
       ($self->{login_href}->{restUrl} eq "") ) {
      $self->add_error("login: Did not get REST URL");
      return 1;
   }
   elsif( (! exists $self->{login_href}->{BhRestToken} ) ||
          ($self->{login_href}->{BhRestToken} eq "")   ) {
      $self->add_error("login: Did not get REST TOKEN");
      return 1;
   }

   
   return 0;
}





#----------------------------------------------------------------------
#
# NAME:  get_entity
#
# DESC:  Get a single Entity
#
# https://rest5.bullhornstaffing.com/rest-services/1zsyw4/
#     entity/123456/Candidate?
#     BhRestToken=74e6ae9b-b5c2-41d0-867f-f6b7a36f16db
#     fields=firstName,lastName,address,email
#
#  JSON Returned
#
# {
#   "data" : {
#     "firstName" : "Cheryl",
#     "lastName" : "Bullhorn",
#     "address" : {
#       "address1" : "1234, West Nowhere Street",
#       "address2" : "",
#       "city" : "Carlisle",
#       "state" : "Massachusetts",
#       "zip" : "01741",
#       "countryID" : 1,
#       "countryName" : "United States",
#       "countryCode" : "US"
#     },
#     "email" : "wrhess@gmail.com",
#     "_score" : 7.84939
#   }
# }
#
#
# ARGS: entity - BH entity name
#       id     - BH Entity ID
#       fields - comma delim list of fields to return
#
#
# RETN:  Search Object from JSON
#
# HIST:  
#
#----------------------------------------------------------------------
sub get_entity {
   my ($self, $entity, $id, $fields) = @_;

   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("get_entity: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("get_entity: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("get_entity: entity not defined");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("get_entity: Problem checking access token");
      return undef;
   }


   my $get = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} . qq(entity/$entity/$id) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken};
   
   $url .= "&" . qq(fields=$fields)   if $fields ne "";
   
   $self->add_debug("get_entity: URL = $url" . "\n");

   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("get_entity: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};
      

   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);
      
      $self->add_debug("get_entity: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $get_json = $res->content;
         
         $self->add_debug("get_entity: $get_json")  if $self->{debug_http};
         
         $get = $self->{json}->decode($get_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("get_entity: successful on try $tries");
         }
      }
      else {
         $self->add_error("get_entity: HTTP call failed");
         $self->add_error("get_entity: ". $res->status_line);
         $self->add_error("get_entity: try = $tries");

         # If we don't already have this info in the debug log
         # add it to the error log
         if(! $self->{debug_http}) {
            $self->add_error("get_entity: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("get_entity: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }
      
         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};
      }
   }

   
   if( ! exists $get->{data} ) {
      $self->add_error("get_entity: Did not get info for $entity ($id)");
   }


   return $get;
}





#----------------------------------------------------------------------
#
# NAME:  get_entity_files
#
# DESC:  Get file list for a single Entity
#
#
#  JSON Returned
#
#
#
# ARGS: entity - BH entity name
#       id     - BH Entity ID
#
#
# RETN:  Files Object from JSON
#
# HIST:  
#
#----------------------------------------------------------------------
sub get_entity_files {
   my ($self, $entity, $id, $fields) = @_;

   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("get_entity_files: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("get_entity_files: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("get_entity_files: entity not defined");
      return undef;
   }

   if( $id eq "") {
      $self->add_error("get_file: Entity ID not defined");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("get_entity_files: Problem checking access token");
      return undef;
   }

       
   my $get = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} .
       qq(entity/$entity/$id/fileAttachments) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken};

   $url .= "&" . qq(fields=$fields)   if $fields ne "";
   
   $self->add_debug("get_entity_files: URL = $url" . "\n");
   
   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("get_entity_files: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);

      $self->add_debug("get_entity_files: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $get_json = $res->content;
         
         $self->add_debug("get_entity_files: $get_json");
         
         $get = $self->{json}->decode($get_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("get_entity_files: successful on try $tries");
         }
      }
      else {
         $self->add_error("get_entity_files: HTTP call failed");
         $self->add_error("get_entity_files: ". $res->status_line);
         $self->add_error("get_entity_files: try = $tries");

         # If we don't already have this info in the debug log
         # add it to the error log
         if(! $self->{debug_http}) {
            $self->add_error("get_entity_files: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("get_entity_files: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }
      
         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};
      }
   }

   
   if( ! exists $get->{data} ) {
      $self->add_error("get_entity_files: Did not get files for $entity ($id)");
   }


   return $get;
}





#----------------------------------------------------------------------
#
# NAME:  get_file
#
# DESC:  Get file for an Entity
#
#
#  JSON Returned
#
#
#
# ARGS: entity - BH entity name
#       id     - BH Entity ID
#       fileid - BH File ID on the Entity
#
#
# RETN:  File Object from JSON
#
# HIST:  
#
#----------------------------------------------------------------------
sub get_file {
   my ($self, $entity, $id, $fileid) = @_;

   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("get_file: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("get_file: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("get_file: entity not defined");
      return undef;
   }

   if( $id eq "") {
      $self->add_error("get_file: Entity ID not defined");
      return undef;
   }

   if( $fileid eq "") {
      $self->add_error("get_file: File ID not defined");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("get_file: Problem checking access token");
      return undef;
   }

       
   my $get = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} .
       qq(file/$entity/$id/$fileid) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken};

   $self->add_debug("get_file: URL = $url" . "\n");
   

   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("get_file: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
      
      my $res = $self->{ua}->request($req);

      $self->add_debug("get_file: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $get_json = $res->content;
         
         $self->add_debug("get_file: $get_json");
         
         $get = $self->{json}->decode($get_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("get_file: successful on try $tries");
         }
      }
      else {
         $self->add_error("get_file: HTTP call failed");
         $self->add_error("get_file: ". $res->status_line);
         $self->add_error("get_file: try = $tries");

         # If we don't already have this info in the debug log
         # add it to the error log
         if(! $self->{debug_http}) {
            $self->add_error("get_file: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("get_file: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }
      
         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};
      }
   }


   return $get;
}






#----------------------------------------------------------------------
#
# NAME:  search_entity
#
# DESC:  Search for an Entity
#
# https://rest5.bullhornstaffing.com/rest-services/1zsyw4/search/Candidate?
#     BhRestToken=74e6ae9b-b5c2-41d0-867f-f6b7a36f16db
#     query=email:"wrhess@gmail.com"
#     fields=firstName,lastName,address,email
#
#  JSON Returned
#
# {
#   "total" : 1,
#   "start" : 0,
#   "count" : 1,
#   "data" : [ {
#     "firstName" : "Cheryl",
#     "lastName" : "Bullhorn",
#     "address" : {
#       "address1" : "1234, West Nowhere Street",
#       "address2" : "",
#       "city" : "Carlisle",
#       "state" : "Massachusetts",
#       "zip" : "01741",
#       "countryID" : 1,
#       "countryName" : "United States",
#       "countryCode" : "US"
#     },
#     "email" : "wrhess@gmail.com",
#     "_score" : 7.84939
#   } ]
# }
#
# NOTE: there seems to be a bunch of extra spaces at the end of 
#       countryName - total width seems to be fixed at 64 chars
#
#
# ARGS: entity - BH entity name
#       query  - string using field:value BH format
#       fields - comma delim list of fields to return
#       sort   - field to sort by
#       count  - number of results to return (default 20 - max 500)
#       start  - record number to return
#
#
# RETN:  Search Object from JSON
#
# HIST:  
#
#----------------------------------------------------------------------
sub search_entity {
   my ($self, $entity, $query, $fields, $sort, $count, $start) = @_;

   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("search_entity: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("search_entity: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("search_entity: entity not defined");
      return undef;
   }

   if( $query eq "") {
      $self->add_error("search_entity: query not defined");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("search_entity: Problem checking access token");
      return undef;
   }

       
   my $search = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} . qq(search/$entity) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken} . "&" .
       qq(query=$query);

   $url .= "&" . qq(fields=$fields)   if $fields ne "";
   $url .= "&" . qq(sort=$sort)       if $sort   ne "";
   $url .= "&" . qq(count=$count)     if $count  ne "";
   $url .= "&" . qq(start=$start)     if $start  ne "";
   
   $self->add_debug("search_entity: URL = $url" . "\n") if $self->{debug_http};
   
   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("search_entity: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;
   
   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
      
      my $res = $self->{ua}->request($req);
      
      $self->add_debug("search_entity: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $search_json = $res->content;
         
         $self->add_debug("search_entity: $search_json") if $self->{debug_http};
         
         $search  = $self->{json}->decode($search_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("search_entity: successful on try $tries");
         }
      }
      else {
         $self->add_error("search_entity: HTTP call failed");
         $self->add_error("search_entity: ". $res->status_line);
         
         # If we don't already have this info in the debug log
         # add it to the error log
         if(! $self->{debug_http}) {
            $self->add_error("search_entity: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("search_entity: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }
      

         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};
      }
   }

   
   if( ! exists $search->{total} ) {
      $self->add_error("search_entity: Did not get search info");
   }


   return $search;
}





#----------------------------------------------------------------------
#
# NAME:  search_entity_id
#
# DESC:  Search for an Entity by ID
#
# ARGS:  id - Entity ID
#
# RETN:  Search Object from JSON
#
# HIST:  
#
#----------------------------------------------------------------------
sub search_entity_id {
   my ($self, $type, $id, $fields) = @_;

   my $query = qq(id:"$id") if $id ne "";

   if( $type eq "") {
      $self->add_error("search_entity_id: entity type not defined");
      return undef;
   }
   
   if( $query eq "") {
      $self->add_error("search_entity_id: query is empty");
      return undef;
   }
      
   return $self->search_entity($type, $query, $fields);
}



#----------------------------------------------------------------------
#
# NAME:  search_candidate_name
#
# DESC:  Search for a Candidate by Name
#
# ARGS:  last  - Last Name
#        first - First Name (optional)
#
# RETN:  Search Object from JSON
#
# HIST:  
#
#----------------------------------------------------------------------
sub search_candidate_name {
   my ($self, $first, $last, $fields, $sort, $count, $start) = @_;

   my $query = "";

   if($first ne "") {
      $query .= " AND " if $query ne "";
      $query .= qq(firstName:"$first");
   }   

   if($last ne "") {
      $query .= " AND " if $query ne "";
      $query .= qq(lastName:"$last");
   }



   if( $query eq "") {
      $self->add_error("search_candidate_name: query is empty");
      return undef;
   }
   
   
   return $self->search_entity("Candidate", $query, 
                               $fields, $sort, $count, $start);
}



#----------------------------------------------------------------------
#
# NAME:  search_candidate_email
#
# DESC:  Search for a Candidate by email
#
# ARGS:  email - Last Name
#
# RETN:  Search Object from JSON
#
# HIST:  
#
#----------------------------------------------------------------------
sub search_candidate_email {
   my ($self, $email, $fields, $sort, $count, $start) = @_;

   if( $email eq "") {
      $self->add_error("search_candidate_email: Email not defined");
      return 1;
   }

   my $query = qq(email:"$email");

   return $self->search_entity("Candidate", $query, 
                               $fields, $sort, $count, $start);
}





#----------------------------------------------------------------------
#
# NAME:  query_entity
#
# DESC:  Query for an Entity
#
# https://rest5.bullhornstaffing.com/rest-services/1zsyw4/query/Candidate?
#     BhRestToken=74e6ae9b-b5c2-41d0-867f-f6b7a36f16db
#     where=id=%20337228%20AND%20status='Active'
#     fields=firstName,lastName,address,email
#
#
# NOTE: The query function does not seem to work for Candidates
#
#
#
#  JSON Returned
#
# {
#   "start" : 0,
#   "count" : 1,
#   "data" : [ {
#     "firstName" : "Cheryl",
#     "lastName" : "Bullhorn",
#     "address" : {
#       "address1" : "1234, West Nowhere Street",
#       "address2" : "",
#       "city" : "Carlisle",
#       "state" : "Massachusetts",
#       "zip" : "01741",
#       "countryID" : 1,
#       "countryName" : "United States",
#       "countryCode" : "US"
#     },
#     "email" : "wrhess@gmail.com",
#     "_score" : 7.84939
#   } ]
# }
#
# NOTE: there seems to be a bunch of extra spaces at the end of 
#       countryName - total width seems to be fixed at 64 chars
#
#
# ARGS: * entity  - BH entity name
#       * where   - string using field:value BH format
#       * fields  - comma delim list of fields to return
#         orderby - fields to sort by
#         count   - number of results to return (default 20 - max 500)
#         start   - record number to return
#
#
# RETN:  Returned Query Object from JSON
#
# HIST:  
#
#----------------------------------------------------------------------
sub query_entity {
   my ($self, $entity, $where, $fields, $orderby, $count, $start) = @_;

   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("query_entity: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("query_entity: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("query_entity: entity not defined");
      return undef;
   }

   if( $where eq "") {
      $self->add_error("query_entity: where clause not defined");
      return undef;
   }

   if( $fields eq "") {
      $self->add_error("query_entity: fields not defined");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("query_entity: Problem checking access token");
      return undef;
   }
   

   my $query = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} . qq(query/$entity)    . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken} . "&" .
       qq(where=)       . uri_escape($where)                 . "&" .
       qq(fields=)      . $fields;

   $url .= "&" . qq(orderBy=$orderby) if $orderby ne "";
   $url .= "&" . qq(count=$count)     if $count   ne "";
   $url .= "&" . qq(start=$start)     if $start   ne "";
   
   $self->add_debug("query_entity: URL = $url" . "\n") if $self->{debug_http};
   
   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("query_entity: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
      
      my $res = $self->{ua}->request($req);
      
      $self->add_debug("query_entity: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $query_json = $res->content;
         
         $self->add_debug("query_entity: $query_json") if $self->{debug_http};
         
         $query   = $self->{json}->decode($query_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("query_entity: successful on try $tries");
         }
      }
      else {
         $self->add_error("query_entity: HTTP call failed");
         $self->add_error("query_entity: ". $res->status_line);
         $self->add_error("query_entity: try = $tries");
         
         # If we don't already have this info in the debug log
         # add it to the error log.
         if(! $self->{debug_http}) {
            $self->add_error("query_entity: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("query_entity: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }
      
         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};         
      }
   }

   
   if( ! exists $query->{count} ) {
      $self->add_error("query_entity: Did not get query info");
   }


   return $query;
}



#----------------------------------------------------------------------
#
# NAME:  query_entity_id
#
# DESC:  Query for an Entity by ID
#
# ARGS:  id - Entity ID
#
# RETN:  Search Object from JSON
#
# HIST:  
#
#----------------------------------------------------------------------
sub query_entity_id {
   my ($self, $type, $id, $fields) = @_;

   my $query = qq(id=$id) if $id ne "";

   if( $type eq "") {
      $self->add_error("query_entity_id: entity type not defined");
      return undef;
   }
   
   if( $query eq "") {
      $self->add_error("query_entity_id: query is empty");
      return undef;
   }
      
   return $self->query_entity($type, $query, $fields);
}




#----------------------------------------------------------------------
#
# NAME:  parse_resume
#
# DESC:  Upload a Resume and get Candidate JSON back
#
# ARGS:  file - path to the resume
#               this will look at extension for format setting
#
# RETN:  Candidate Object from JSON
#
# HIST:  
#
#----------------------------------------------------------------------
sub parse_resume {
   my ($self, $file) = @_;

   if( ! -e $file ) {
      $self->add_error("parse_resume: restUrl not defined");
      return undef;
   }

   my $format = (split /\./, File::Basename::basename($file))[1];

   if( $format eq "" ) {
      $self->add_error("parse_resume: format not defined");
      return undef;
   }
   
   if( ! grep /^$format$/i, qw(text html pdf doc docx rtf odt) ) {
      $self->add_error("parse_resume: format not supported");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("parse_resume: Problem checking access token");
      return undef;
   }
      
   
   my $url = 
       $self->{login_href}->{restUrl} . qq(resume/parseToCandidate) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken} . "&" .
       qq(format=$format);

   $self->add_debug("parse_resume: URL = $url" . "\n") if $self->{debug_http};

   my $req = POST $url,
       Content_Type => 'multipart/form-data',
       Content => [ file => [ $file ] ];

   $self->add_debug("parse_resume: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};
   
   my $candidate = undef;
   
   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);

      $self->add_debug("parse_resume: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
   
      if($res->is_success) {
         my $candidate_json = $res->content;
         
         $self->add_debug("parse_resume: $candidate_json")
             if $self->{debug_http};
         
         $candidate = $self->{json}->decode($candidate_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("parse_resume: successful on try $tries");
         }
      }
      else {
         $self->add_error("parse_resume: HTTP call failed");
         $self->add_error("parse_resume: ". $res->status_line);
         $self->add_error("parse_resume: try = $tries");

         # If we don't already have this info in the debug log
         # add it to the error log
         if(! $self->{debug_http}) {
            $self->add_error("parse_resume: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("parse_resume: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }
      
         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};
      }
   }
   

   if( ! exists $candidate->{candidate} ) {
      $self->add_error("parse_resume: Did not get candidate info");
   }
   
      
   return $candidate;   
}





#----------------------------------------------------------------------
#
# NAME:  create_entity
#
# DESC:  Create an Entity
#
# https://rest5.bullhornstaffing.com/rest-services/1zsyw4/entity/Candidate?
#     BhRestToken=74e6ae9b-b5c2-41d0-867f-f6b7a36f16db
#
#  JSON Returned
#
# {
#     "changedEntityType" : "Candidate",
#     "changedEntityId"   : 123111,
#     "changeType"        : "INSERT",
#     "data" : {
#                "email" : "bhess@techrg123.com",
#                "lastName" : "Bullhorn",
#                "description" : "Here is my description",
#                "firstName" : "Billy",
#                "name" : "Billy Bullhorn"
#               }
#  }
#
#
#
# ARGS: entity - BH entity name
#       href   - Perl hash ref that will be converted into JSON 
#                to create the entity
#
# RETN:  JSON that gives the Entity ID
#
# HIST:  
#
#----------------------------------------------------------------------
sub create_entity {
   my ($self, $entity, $entity_href) = @_;

   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("create_entity: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("create_entity: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("create_entity: Entity not supplied");
      return undef;
   }

   if( ref $entity_href ne "HASH") {
      $self->add_error("create_entity: data needs to be hasf ref");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("create_entity: Problem checking access token");
      return undef;
   }
   

   my $create = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} . qq(entity/$entity) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken};

   $self->add_debug("create_entity: URL = $url" . "\n") if $self->{debug_http};
   
   my $req = HTTP::Request->new(PUT => $url);

   my $content_json = $self->{json}->pretty->encode($entity_href);
   $self->add_debug("create_entity: $content_json") if $self->{debug_http};
   $req->content($content_json);

   $self->add_debug("create_entity: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};
   


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);

      $self->add_debug("create_entity: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $create_json = $res->content;
         
         $self->add_debug("create_entity: $create_json") if $self->{debug_http};
         
         $create = $self->{json}->decode($create_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("create_entity: successful on try $tries");
         }
      }
      else {
         $self->add_error("create_entity: HTTP call failed");
         $self->add_error("create_entity: ". $res->status_line);
         $self->add_error("create_entity: try = $tries");

         # If we don't already have this info in the debug log
         # add it to the error log
         if(! $self->{debug_http}) {
            $self->add_error("create_entity: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("create_entity: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }
         
         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};
      }
   }

   
   if( ! exists $create->{changedEntityId} ) {
      $self->add_error("create_entity: Did not get Entity ID back");
   }


   return $create;
}






#----------------------------------------------------------------------
#
# NAME:  update_entity
#
# DESC:  Update an Entity
#
# https://rest5.bullhornstaffing.com/
#     rest-services/1zsyw4/entity/Candidate/121172?
#     BhRestToken=74e6ae9b-b5c2-41d0-867f-f6b7a36f16db
#
#  JSON Returned
#
# {
#     "changedEntityType" : "Candidate",
#     "changedEntityId"   : 121172,
#     "changeType"        : "UPDATE",
#     "data" : {
#                "email" : "bhess@techrg123.com",
#                "lastName" : "Bullhorn",
#                "firstName" : "Billy",
#                "name" : "Billy Bullhorn"
#               }
#  }
#
#
#
# ARGS: entity - BH entity name
#       id     - BH entity ID
#       href   - Perl hash ref that will be converted into JSON 
#                to update the entity
#
# RETN:  JSON that gives the Entity ID
#
# HIST:  
#
#----------------------------------------------------------------------
sub update_entity {
   my ($self, $entity, $id, $entity_href) = @_;

   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("update_entity: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("update_entity: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("update_entity: Entity not supplied");
      return undef;
   }

   if( $id eq "") {
      $self->add_error("update_entity: Entity ID not supplied");
      return undef;
   }
   
   if( ref $entity_href ne "HASH") {
      $self->add_error("update_entity: data needs to be hash ref");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("update_entity: Problem checking access token");
      return undef;
   }
   

   my $update = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} . qq(entity/$entity/$id) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken};

   $self->add_debug("update_entity: URL = $url" . "\n") if $self->{debug_http};
   
   my $req = HTTP::Request->new(POST => $url);

   my $content_json = $self->{json}->pretty->encode($entity_href);
   $self->add_debug("update_entity: $content_json") if $self->{debug_http};
   $req->content_type("text/plain; charset='utf8'");
   $req->content(Encode::encode_utf8($content_json));
   #$req->content($content_json);

   $self->add_debug("update_entity: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};
   

   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
   
      my $res = $self->{ua}->request($req);

      $self->add_debug("update_entity: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $update_json = $res->content;
         
         $self->add_debug("update_entity: $update_json") if $self->{debug_http};
         
         $update = $self->{json}->decode($update_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("update_entity: successful on try $tries");
         }
      }
      else {
         $self->add_error("update_entity: HTTP call failed");
         $self->add_error("update_entity: ". $res->status_line);
         $self->add_error("update_entity: try = $tries");

         # If we don't already have this info in the debug log
         # add it to the error log
         if(! $self->{debug_http}) {
            $self->add_error("update_entity: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("update_entity: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }
      
         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};
      }
   }
   
   
   if( ! exists $update->{changedEntityId} ) {
      $self->add_error("update_entity: Did not get Entity ID back");
   }


   return $update;
}




#----------------------------------------------------------------------
#
# NAME:  delete_entity
#
# DESC:  Delete an Entity
#        This will only perform a Soft Delete which sets the
#        isDeleted property to true
#
# https://rest5.bullhornstaffing.com/
#     rest-services/1zsyw4/entity/Candidate/121172?
#     BhRestToken=74e6ae9b-b5c2-41d0-867f-f6b7a36f16db
#
#  JSON Returned
#
# {
#     "changedEntityType" : "Candidate",
#     "changedEntityId"   : 121172,
#     "changeType"        : "UPDATE",
#     "data"              :  { isDeleted : true }
#  }
#
#
#
# ARGS: entity - BH entity name
#       id     - BH entity ID
#       undel  - Set to 1 if you want to undelete the entity
#                Otherwise do not provide to soft delete the entity
#                
#
# RETN:  JSON that gives the Entity ID
#
# HIST:  
#
#----------------------------------------------------------------------
sub delete_entity {
   my ($self, $entity, $id, $undel) = @_;

   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("delete_entity: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("delete_entity: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("delete_entity: Entity not supplied");
      return undef;
   }

   if( $id eq "") {
      $self->add_error("delete_entity: Entity ID not supplied");
      return undef;
   }
   

   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("delete_entity: Problem checking access token");
      return undef;
   }

   
   # Check for Undelete
   if( $undel == 1 ) {
      $undel = JSON::false;
   }
   else {
      $undel = JSON::true;
   }

   
   my $del = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} . qq(entity/$entity/$id) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken};

   $self->add_debug("delete_entity: URL = $url" . "\n") if $self->{debug_http};
   
   my $req = HTTP::Request->new(POST => $url);

   my $content_json = 
       $self->{json}->pretty->encode( { isDeleted => $undel } );

   $self->add_debug("delete_entity: $content_json") if $self->{debug_http};
   $req->content($content_json);

   $self->add_debug("delete_entity: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};
   

   my $success = 0;
   my $tries   = 0;
   
   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);

      $self->add_debug("delete_entity: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
   
      if($res->is_success) {
         my $del_json = $res->content;
         
         $self->add_debug("delete_entity: $del_json") if $self->{debug_http};
         
         $del = $self->{json}->decode($del_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("delete_entity: successful on try $tries");
         }
      }
      else {
         $self->add_error("delete_entity: HTTP call failed");
         $self->add_error("delete_entity: ". $res->status_line);
         $self->add_error("delete_entity: try = $tries");

         # If we don't already have this info in the debug log
         # add it to the error log
         if(! $self->{debug_http}) {
            $self->add_error("delete_entity: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("delete_entity: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }
      
         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};
      }
   }

   
   if( ! exists $del->{changedEntityId} ) {
      $self->add_error("delete_entity: Did not get Entity ID back");
   }


   return $del;
}






#----------------------------------------------------------------------
#
# NAME:  attach_file
#
# DESC:  Attach a file to an Entity
#
# https://rest5.bullhornstaffing.com/rest-services/1zsyw4/Candidate/<ENTITYID>?
#     BhRestToken=74e6ae9b-b5c2-41d0-867f-f6b7a36f16db
#
#  JSON Returned
#
# {
#     "changedEntityType" : "Candidate",
#     "changedEntityId"   : 123111,
#     "changeType"        : "INSERT",
#     "data" : {
#                "email" : "bhess@techrg123.com",
#                "lastName" : "Bullhorn",
#                "description" : "Here is my description",
#                "firstName" : "Billy",
#                "name" : "Billy Bullhorn"
#               }
#  }
#
#
#
# ARGS: * entity    - BH entity name
#       * entity_id - Entity ID
#       * extern_id - 
#       * file      - File to upload and attach to the Entity
#         name      - Name you want to give the file
#                     defaults to the actual file name in previous arg
#         descr     - Description
#         mime_type - mime type ex: text/plain  application/pdf  etc
#         type      - Type of file attached
#                      
#
#
# RETN:  JSON 
#
# HIST:  
#
#----------------------------------------------------------------------
sub attach_file {
   my ( $self, $entity, $entity_id, $file, $extern_id, $name,
        $descr, $mime_type, $type ) = @_;

   if( $self->{login_href}->{restUrl} eq "" ) {
      $self->add_error("attach_file: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "" ) {
      $self->add_error("attach_file: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "" ) {
      $self->add_error("attach_file: Entity not supplied");
      return undef;
   }

   if( $entity_id eq "" ) {
      $self->add_error("attach_file: Entity ID not supplied");
      return undef;
   }

   if( $file eq "" ) {
      $self->add_error("attach_file: File not supplied");
      return undef;
   }

   if( ! -f $file ) {
      $self->add_error("attach_file: File not found");
      return undef;
   }

   if( $extern_id eq "" ) {
      $self->add_error("attach_file: External ID not supplied");
      return undef;
   }

   
   my $fn = File::Basename::basename($file);
   
   # If a name was not supplied then use the actual filename 
   if( $name eq "" ) {
      $name = $fn;
   }


   # Open the file and get base64
   my $f64 = "";
   
   if( open FH, "<", $file ) {
      local $/ = undef;
      $f64 = encode_base64(<FH>);
      close FH;
   }
   else {
      $self->add_error("attach_file: Problem opening '$file' to get base64");
      return undef;
   }
   
   if( $f64 eq "" ) {
      $self->add_error("attach_file: Did not get base64 for '$file'");
      return undef;
   }
   

   my $f = { fileContent => $f64,
             externalID  => $extern_id,
             fileType    => "SAMPLE",
             name        => $name,
             description => $descr,
             contentType => $mime_type,
             type        => $type };

   my $f2 = { fileContent => "FILE MIME::Base64",
              externalID  => $extern_id,
              fileType    => "SAMPLE",
              name        => $name,
              description => $descr,
              contentType => $mime_type,
              type        => $type };
   

   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("attach_file: Problem checking access token");
      return undef;
   }

   
   my $attach = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} . qq(file/$entity/$entity_id) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken};

   $self->add_debug("attach_file: URL = $url" . "\n") if $self->{debug_http};
   
   my $req = HTTP::Request->new(PUT => $url);

   my $debug_json = $self->{json}->pretty->encode($f2);
   $self->add_debug("attach_file: $debug_json") if $self->{debug_http};
   $req->content( $self->{json}->encode($f) );

   $self->add_debug("attach_file: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
   
      my $res = $self->{ua}->request($req);

      $self->add_debug("attach_file: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $attach_json = $res->content;
         
         $self->add_debug("attach_file: $attach_json") if $self->{debug_http};
         
         $attach = $self->{json}->decode($attach_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("attach_file: successful on try $tries");
         }
      }
      else {
         $self->add_error("attach_file: HTTP call failed");
         $self->add_error("attach_file: ". $res->status_line);
         $self->add_error("attach_file: try = $tries");

         # If we don't already have this info in the debug log
         # add it to the error log
         if(! $self->{debug_http}) {
            $self->add_error("attach_file: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("attach_file: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }
      
         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};
      }
   }

   
   if( ! exists $attach->{fileId} ) {
      $self->add_error("attach_file: Did not get File ID back");
   }


   return $attach;
}






#----------------------------------------------------------------------
#
# NAME:  put_subscription
#
# DESC:  
#
# https://rest5.bullhornstaffing.com/rest-services/1zsyw4/
#     event/subsciption/ABC123?
#     BhRestToken=74e6ae9b-b5c2-41d0-867f-f6b7a36f16db
#     type=entity
#     names=Candidate
#     eventTypes=INSERTED,UPDATED,DELETED
#
#  JSON Returned
#
#
#
#
# ARGS: subid  - Subscription ID
#       type   - entity
#       names  - 
#       eventTypes - INSERTED,UPDATED,DELETED
#
#
# RETN:  
#
# HIST:  
#
#----------------------------------------------------------------------
sub put_subscription {
   my ($self, $subid, $type, $names, $eventTypes) = @_;

   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("put_subscription: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("put_subscription: BhRestToken not defined");
      return undef;
   }

   if( $subid eq "") {
      $self->add_error("put_subscription: subid not defined");
      return undef;
   }

   if( $type eq "") {
      $self->add_error("put_subscription: type not defined");
      return undef;
   }

   if( $names eq "") {
      $self->add_error("put_subscription: names not defined");
      return undef;
   }

   if( $eventTypes eq "") {
      $self->add_error("put_subscription: eventTypes not defined");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("put_subscription: Problem checking access token");
      return undef;
   }

   
   my $putsub = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} . qq(event/subscription/$subid) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken} . "&" .
       qq(type=$type)                                        . "&" .
       qq(names=$names)                                      . "&" .
       qq(eventTypes=$eventTypes);

   $self->add_debug("put_subscription: URL = $url" . "\n")
       if $self->{debug_http};
   
   my $req = HTTP::Request->new(PUT => $url);

   $self->add_debug("put_subscription: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
      
      my $res = $self->{ua}->request($req);
      
      $self->add_debug("put_subscription: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $putsub_json = $res->content;
         
         $self->add_debug("put_subscription: $putsub_json")
             if $self->{debug_http};
         
         $putsub = $self->{json}->decode($putsub_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("put_subscription: successful on try $tries");
         }
      }
      else {
         $self->add_error("put_subscription: HTTP call failed");
         $self->add_error("put_subscription: ". $res->status_line);
         $self->add_error("put_subscription: try = $tries");

         # If we don't already have this info in the debug log
         # add it to the error log
         if(! $self->{debug_http}) {
            $self->add_error("put_subscription: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("put_subscription: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }
      
         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};
      }
   }
   
   
   #if( ! exists $search->{total} ) {
   #   $self->add_error("put_subscription: Did not get search info");
   #}


   return $putsub;
}





#----------------------------------------------------------------------
#
# NAME:  get_subscription
#
# DESC:  
#
# https://rest5.bullhornstaffing.com/rest-services/1zsyw4/
#     event/subsciption/ABC123?
#     BhRestToken=74e6ae9b-b5c2-41d0-867f-f6b7a36f16db
#     maxEvents=100
#
#  JSON Returned
#
#  {
#    'requestId' => 2,
#    'events' => 
#        [
#          {
#            'eventId' => 'ID:JBM-60000004',
#            'entityId' => 121172,
#            'eventType' => 'ENTITY',
#            'updatedProperties' => [
#                                     'owner'
#                                    ],
#            'eventMetadata' => {
#                     'PERSON_ID' => '123002',
#                     'TRANSACTION_ID' => '0e05f5b4-dbcb-4bca-b096-0c535c0e27cf'
#                                },
#            'entityName' => 'Candidate',
#            'entityEventType' => 'UPDATED',
#            'eventTimestamp' => '1488225753923'
#           }
#         ]
#   };
#
#
# ARGS: * subid     - Subscription ID
#       * maxEvents - Max number of events to return
#         reqid     - Previous Request ID to reget
#
#
# RETN:  
#
# HIST:  
#
#----------------------------------------------------------------------
sub get_subscription {
   my ($self, $subid, $maxEvents, $reqid) = @_;

   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("get_subscription: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("get_subscription: BhRestToken not defined");
      return undef;
   }

   if( $subid eq "") {
      $self->add_error("get_subscription: subid not defined");
      return undef;
   }

   if( $maxEvents eq "") {
      $self->add_error("get_subscription: maxEvents not defined");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("get_subscription: Problem checking access token");
      return undef;
   }

   
   my $getsub = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} . qq(event/subscription/$subid) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken} . "&" .
       qq(maxEvents=$maxEvents);

   $url .= "&" . qq(requestId=$reqid) if ($reqid ne "") || ($reqid > 0);

   
   $self->add_debug("get_subscription: URL = $url" . "\n")
       if $self->{debug_http};
   
   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("get_subscription: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};
   

   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);

      $self->add_debug("get_subscription: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $getsub_json = $res->content;
         
         $self->add_debug("get_subscription: $getsub_json")
             if $self->{debug_http};
         
         $getsub = $self->{json}->decode($getsub_json) if $getsub_json ne "";

         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("get_subscription: successful on try $tries");
         }
      }
      else {
         $self->add_error("get_subscription: HTTP call failed");
         $self->add_error("get_subscription: ". $res->status_line);
         $self->add_error("get_subscription: try = $tries");

         # If we don't already have this info in the debug log
         # add it to the error log
         if(! $self->{debug_http}) {
            $self->add_error("get_subscription: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("get_subscription: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }
      
         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};
      }
   }

   
   return $getsub;
}




#----------------------------------------------------------------------
#
# NAME:  delete_subscription
#
# DESC:  
#
# https://rest5.bullhornstaffing.com/rest-services/1zsyw4/
#     event/subsciption/ABC123?
#     BhRestToken=74e6ae9b-b5c2-41d0-867f-f6b7a36f16db
#
#  JSON Returned
#
#    {'result': True}
#
#
# ARGS: * subid     - Subscription ID
#
#
# RETN:  
#
# HIST:  
#
#----------------------------------------------------------------------
sub delete_subscription {
   my ($self, $subid) = @_;

   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("delete_subscription: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("delete_subscription: BhRestToken not defined");
      return undef;
   }

   if( $subid eq "") {
      $self->add_error("delete_subscription: subid not defined");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("delete_subscription: Problem checking access token");
      return undef;
   }

   
   my $delsub = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} . qq(event/subscription/$subid) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken};

   
   $self->add_debug("delete_subscription: URL = $url" . "\n")
       if $self->{debug_http};
   
   my $req = HTTP::Request->new(DELETE => $url);

   $self->add_debug("delete_subscription: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   
   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);

      $self->add_debug("delete_subscription: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $delsub_json = $res->content;
         
         $self->add_debug("delete_subscription: $delsub_json")
             if $self->{debug_http};
         
         $delsub = $self->{json}->decode($delsub_json) if $delsub_json ne "";
         
         $success = 1;

         # If we had to retry, write a success msg to the error log
         if($tries > 1) {
            $self->add_error("delete_subscription: successful on try $tries");
         }
      }
      else {
         $self->add_error("delete_subscription: HTTP call failed");
         $self->add_error("delete_subscription: ". $res->status_line);
         $self->add_error("delete_subscription: try = $tries");

         # If we don't already have this info in the debug log
         # add it to the error log
         if(! $self->{debug_http}) {
            $self->add_error("delete_subscription: HTTP REQUEST:\n" . 
                             $req->as_string . "\n");
            $self->add_error("delete_subscription: HTTP RESPONSE:\n" . 
                             $res->as_string . "\n");
         }
      
         # Pause before trying again
         sleep $self->{retry_wait} if $tries < $self->{retry_max};
      }
   }

   
   return $delsub;
}










#----------------------------------------------------------------------
#
# NAME:  date/time functions
#
# DESC:  Various time functions
#
#        Bullhorn keeps datetime as epoch seconds with milliseconds
#        that is the reason all epoch secs below are mult/div by 1000
#
#        The search function for entities in Bullhorn uses Lucene
#        which expects the date to be in the format: yyyymmdd
#                      and time to be in the format: yyyymmddTHH:MM:SS
#
# ARGS: 
#
# RETN:  
#
# HIST:  
#
#----------------------------------------------------------------------
sub ts_epoch_now {
   return time * 1000;
}

sub ts_lucene_now {
   return $_[0]->ts_epoch_to_lucene(localtime(time));
}

sub ts_mysql_now {
   return $_[0]->ts_epoch_to_mysql(localtime(time));
}

sub ts_epoch_to_mysql {
   my @d = localtime($_[1] / 1000);
   return sprintf("%04d-%02d-%02d %02d:%02d:%02d", 
                  $d[5]+1900, $d[4]+1, $d[3], $d[2], $d[1], $d[0]);
}

sub ts_epoch_to_lucene {
   my @d = localtime($_[1] / 1000);
   return sprintf("%04d%02d%02dT%02d:%02d:%02d", 
                  $d[5]+1900, $d[4]+1, $d[3], $d[2], $d[1], $d[0]);
}

sub ts_epoch_to_date8 {
   my @d = localtime($_[1] / 1000);
   return sprintf "%04d%02d%02d", $d[5]+1900, $d[4]+1, $d[3];
}

sub ts_epoch_to_datetime14 {
   my @d = localtime($_[1] / 1000);
   return sprintf "%04d%02d%02d%02d%02d%02d",
       $d[5]+1900, $d[4]+1, $d[3], $d[2], $d[1], $d[0];
}

sub ts_mysql_to_epoch {
   return timelocal( reverse split /[\-\s+\:]/, $_[1] ) * 1000; 
}

sub ts_lucene_to_epoch {
   my ($d, $t) = split /T/, $_[1];
   my $year = substr $d, 0, 4;
   my $mon  = substr $d, 4, 2;
   my $day  = substr $d, 6, 2;
   my ($hour, $min, $sec) = split /\:/, $t;
   return timelocal( $sec, $min, $hour, $day, $mon, $year ) * 1000; 
}

# '2014-03-17T22:16:53-04:00' ==> '2014-03-17 22:16:53'
sub ts_lucene_to_mysql {
   my $ts = $_[1];
   $ts =~ s/^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2}).*/$1 $2/;

   return $ts;
}

sub get_datetime {
   my @d = localtime(time);
   return sprintf("%04d%02d%02d%02d%02d%02d",
                  $d[5]+1900, $d[4]+1, $d[3], $d[2], $d[1], $d[0]);
}



#======================================================================
# END OF Bullhorn.pm
#======================================================================
1;




