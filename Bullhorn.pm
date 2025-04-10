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
             oauth_url      => '',
             rest_url       => '',
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
   my $json = JSON->new->allow_nonref->utf8;

   $d->{json} = $json;


   #------------------------------------------------------------
   # LWP Object
   #------------------------------------------------------------   
   my $ua = new LWP::UserAgent;

   $ua->timeout( $d->{http_timeout} );


   # Proxy Setup
   #$ua->proxy( 'http',  $d->{http_proxy} )  if $d->{http_proxy}  ne "";
   #$ua->proxy( 'https', $d->{https_proxy} ) if $d->{https_proxy} ne "";

   #$req->proxy_authorization_basic("", "");
   
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
#
# The first call is a GET to the URL below which nicludes the USER ID
# assigned by Bullhorn for the REST API.  This returns the JSON below
# which contains various URLs - we are interested in oauthUrl and restUrl
# These are used to make calls to get/refresh the access token and login.
# If these URLs are not used then Bullhorn servers may redirect HTTP
# calls by returning a 307 code with a Location which this lib would
# have to handle.
#
# Once logged in another restUrl will be returned and set in
# login_href and it will be used for all other REST API calls.
#
#
# https://rest.bullhornstaffing.com/rest-services/loginInfo?username=trc.restapi
#
# {
#  "atsUrl":"https://cls33.bullhornstaffing.com",
#  "billingSyncUrl":"https://wfr-west.bullhornstaffing.com/billing-sync-services",
#  "coreUrl":"https://cls33.bullhornstaffing.com/core",
#  "documentEditorUrl":"https://docs-east.bullhornstaffing.com/document/",
#  "mobileUrl":"https://m-west.bullhorn.com",
#  "oauthUrl":"https://auth-west.bullhornstaffing.com/oauth",
#  "restUrl":"https://rest-west.bullhornstaffing.com/rest-services",
#  "samlUrl":"http://cls33.bullhornstaffing.com/BullhornStaffing/SAML/Login.cfm",
#  "novoUrl":"https://app.bullhornstaffing.com",
#  "pulseInboxUrl":"https://pulse-inbox.bullhornstaffing.com",
#  "canvasUrl":"https://lasbigateway.bullhorn.com/canvas/cgi-bin/cognosisapi.dll",
#  "npsSurveyUrl":"https://surveys-west.bullhorn.com{{path}}?sl=33&{{params}}",
#  "ulUrl":"https://lasuniversal.bullhornstaffing.com/universal-login",
#  "dataCenterId":3,
#  "superClusterId":33
# }
#
#
#
# The second call should redirect back to the provided URL since that
# is the address we gave BH during setup of the API user.
# So we need to check the previous header to get 'Location'
# and get the auth code from the query string where param = 'code'
#
# https://auth.bullhornstaffing.com/oauth/authorize?
#    client_id=<CLIENT ID>
#    response_type=code
#    username=<USER ID>
#    password=<PASSWORD>
#    action=Login
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

   my $func = "get_auth_code";
   
   if( $self->{client_id} eq "") {
      $self->add_error("$func: client_id not defined");
      return 1;
   }

   if( $self->{user_id} eq "") {
      $self->add_error("$func: user_id not defined");
      return 1;
   }

   if( $self->{user_pw} eq "") {
      $self->add_error("$func: user_pw not defined");
      return 1;
   }


   #------------------------------------------------------------
   # Call Bullhorn loginInfo to get URLs to use
   #------------------------------------------------------------   
   my $rest_url = "https://rest.bullhornstaffing.com/rest-services";
   $rest_url = $self->{rest_url} if $self->{rest_url} ne "";
   
   my $url_info =
       $rest_url . "/loginInfo?username=" . $self->{user_id};

   $self->add_debug("$func: URL INFO = $url_info" . "\n")
       if $self->{debug_http};
   
   my $req_info = HTTP::Request->new(GET => $url_info);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req_info->as_string . "\n") if $self->{debug_http};

   my $info_href = { };
   
   my $success = 0;
   my $tries   = 0;
   
   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res_info = $self->{ua}->request($req_info);

      $self->add_debug(
         "$func: HTTP RESPONSE:\n" . 
         $res_info->as_string . "\n") if $self->{debug_http};
   
      my $info_href_json;
      
      if($res_info->is_success) {
         $info_href_json = $res_info->content;
         
         $self->add_debug("$func: $info_href_json")
             if $self->{debug_http};
         
         $info_href = $self->{json}->decode($info_href_json);
         $success   = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req_info, $res_info, $tries);
      }
   }
   

   
   # Assign OAuth and REST URLs
   if( $info_href ) {
      if( exists $info_href->{oauthUrl} &&
          ($info_href->{oauthUrl} ne "") ) {
         $self->{oauth_url} = $info_href->{oauthUrl};
      }
      
      if( exists $info_href->{restUrl} &&
          ($info_href->{restUrl} ne "") ) {
         $self->{rest_url} = $info_href->{restUrl};
      }
   }
   else {
      $self->add_error("$func: ERROR: " .
                       "Problem getting OAuth and REST URLs");
   }


   if( $self->{oauth_url} eq "" ) {
      $self->add_error("$func: ERROR: OAuth URL is not set\n");
      return 1;
   }

   if( $self->{rest_url} eq "" ) {
      $self->add_error("$func: ERROR: REST URL is not set\n");
      return 1;
   }


   
   
   #------------------------------------------------------------
   # Make the call to Login
   #------------------------------------------------------------
   my $url = 
       $self->{oauth_url} . "/authorize?" .
       qq(client_id=) . $self->{client_id} . "&" . 
       qq(response_type=code)              . "&" .
       qq(username=) . $self->{user_id}    . "&" .
       qq(password=) . $self->{user_pw}    . "&" . 
       qq(action=Login);

   $self->add_debug("$func: URL = $url" . "\n") if $self->{debug_http};
   
   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
   
      my $res = $self->{ua}->request($req);

      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};

      if($res->is_success) {
         my $redirect_url = $res->previous->header('Location');

         $self->add_debug("$func: LOC = $redirect_url")
             if $self->{debug_http};
      
         if( $redirect_url =~ /code=(.*)\&/ ) {
            $self->{auth_code} = $1;
         }

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
      }
   }
   
   
   if( $self->{auth_code} eq "" ) {
      $self->add_error("$func: ERROR: Did not get auth code");
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
#     "access_token"  : "5:a6477004-44ee-4d22-a7e8-58105a6a4bef",
#     "token_type"    : "Bearer",
#     "expires_in"    : 600,
#     "refresh_token" : "5:3daca6ef-6d12-4db4-b6d3-8da8a7a27b11"
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

   my $func = "get_access_token";
   
   if( $self->{client_id} eq "") {
      $self->add_error("$func: client_id not defined");
      return 1;
   }

   if( $self->{client_secret} eq "") {
      $self->add_error("$func: client_secret not defined");
      return 1;
   }
   
   if( $self->{auth_code} eq "") {
      $self->add_error("$func: auth_code not defined");
      return 1;
   }


   # Initialize the timestamp for getting the access token
   $self->{access_ts} = 0;


   my $url = 
       $self->{oauth_url} . "/token?" .
       qq(grant_type=authorization_code)                 . "&" .
       qq(code=) . $self->{auth_code}                    . "&" . 
       qq(client_id=) . $self->{client_id}               . "&" .
       qq(client_secret=) . $self->{client_secret};

   $self->add_debug("$func: URL = $url" . "\n")
       if $self->{debug_http};
   
   my $req = HTTP::Request->new(POST => $url);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);

      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
   
      my $access_href_json;
   
      if($res->is_success) {
         $access_href_json = $res->content;
         
         $self->add_debug("$func: $access_href_json")
             if $self->{debug_http};
         
         $self->{access_href} = $self->{json}->decode($access_href_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
      }
   }
   

   if( (! exists $self->{access_href}->{access_token} ) ||
       ($self->{access_href}->{access_token} eq "")  ) {
      $self->add_error("$func: ERROR: Did not get access_token");
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
#     "access_token"  : "5:a6472004-74ff-4d33-a7e8-91105a6a4bed",
#     "token_type"    : "Bearer",
#     "expires_in"    : 600,
#     "refresh_token" : "5:3daca6de-6d12-4dc7-b6d3-3da8a7a27b08"
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

   my $func = "refresh_access_token";
   
   if( $self->{client_id} eq "") {
      $self->add_error("$func: client_id not defined");
      return 1;
   }

   if( $self->{client_secret} eq "") {
      $self->add_error("$func: client_secret not defined");
      return 1;
   }
   
   if( $self->{access_href}->{refresh_token} eq "") {
      $self->add_error("$func: refresh_token not defined");
      return 1;
   }


   # Initialize the timestamp for getting the access token
   $self->{access_ts} = 0;


   my $url = 
       $self->{oauth_url} . "/token?" .
       qq(grant_type=refresh_token)                               . "&" .
       qq(refresh_token=) . $self->{access_href}->{refresh_token} . "&" . 
       qq(client_id=) . $self->{client_id}                        . "&" .
       qq(client_secret=) . $self->{client_secret};

   $self->add_debug("$func: URL = $url" . "\n")
       if $self->{debug_http};
   
   my $req = HTTP::Request->new(POST => $url);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
   
      my $res = $self->{ua}->request($req);
   
      if($res->is_success) {
         my $access_href_json = $res->content;
         
         $self->add_debug("$func: $access_href_json")
             if $self->{debug_http};
         
         $self->{access_href} = $self->{json}->decode($access_href_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
      }
   }

   
   if( (! exists $self->{access_href}->{access_token} ) ||
       ($self->{access_href}->{access_token} eq "")  ) {
      $self->add_error("$func: ERROR: Did not refresh access_token");
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

   my $func = "check_access_token";
   
   # Determine how long we have been using the current token
   # Add 20 seconds 
   my $d = time - $self->{access_ts};

   $self->add_debug("$func: time diff = $d")
       if $self->{debug_http};
   
   my $rc = 0;

   if( $d > ($self->{access_href}->{expires_in} - 20) ) {
      $rc = $self->refresh_access_token;      
      $self->add_debug("$func: refresh token - RET = $rc");      
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
#    "BhRestToken":"8b92f340-5edf-5bfe-1c52-479f2cf3ea47",
#    "restUrl":"https://rest5.bullhornstaffing.com/rest-services/abc123/"
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

   my $func = "login";
   
   if( $self->{access_href}->{access_token} eq "") {
      $self->add_error("$func: access_token not defined");
      return 1;
   }


   my $url =
       $self->{rest_url} . "/login?" .
       qq(version=*) . "&" .
       qq(access_token=) . $self->{access_href}->{access_token};

   $self->add_debug("$func: URL = $url" . "\n");
   
   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
   
      my $res = $self->{ua}->request($req);

      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $login_json = $res->content;
         
         $self->add_debug("$func: $login_json");
         
         $self->{login_href} = $self->{json}->decode($login_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
      }
   }
   

   
   if( (! exists $self->{login_href}->{restUrl} ) ||
       ($self->{login_href}->{restUrl} eq "") ) {
      $self->add_error("$func: ERROR: Did not get REST URL");
      return 1;
   }
   elsif( (! exists $self->{login_href}->{BhRestToken} ) ||
          ($self->{login_href}->{BhRestToken} eq "")   ) {
      $self->add_error("$func: ERROR: Did not get REST TOKEN");
      return 1;
   }

   
   return 0;
}



#----------------------------------------------------------------------
#
# NAME:  connect
#
# DESC:  Function to call the 3 main functions to 
#        initiate the REST API for Bullhorn
#
# ARGS:  
#
# RETN:  0 - Success
#        1 - Error   Check $self->{error_log}
#
# HIST:  
#
#----------------------------------------------------------------------
sub connect {
   my ($self) = @_;

   my $rc;

   $rc = $self->get_auth_code;
   return $rc if $rc;

   $rc = $self->get_access_token;
   return $rc if $rc;

   $rc = $self->login;
   return $rc if $rc;

   return 0;
}




#----------------------------------------------------------------------
#
# NAME:  meta_entity
#
# DESC:  Get the meta data for an Entity
#
# https://rest5.bullhornstaffing.com/rest-services/abc123/
#     meta/Candidate?
#     BhRestToken=74e6ae9b-b5c2-41d0-867f-f6b7a36f16db
#
#
# ARGS: entity - BH entity name
#       fields - comma delim list of fields to return
#
# RETN:  
#
# HIST:  
#
#----------------------------------------------------------------------
sub meta_entity {
   my ($self, $entity, $fields) = @_;

   my $func = "meta_entity";
   
   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("$func: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("$func: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("$func: entity not defined");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("$func: Problem checking access token");
      return undef;
   }


   my $get = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} . qq(meta/$entity) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken};
   
   $url .= "&" . qq(fields=$fields)   if $fields ne "";
   
   $self->add_debug("$func: URL = $url" . "\n");

   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};
      

   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);
      
      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $get_json = $res->content;
         
         $self->add_debug("$func: $get_json")  if $self->{debug_http};
         
         $get = $self->{json}->decode($get_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
      }
   }

   
   if( ! exists $get->{data} ) {
      $self->add_error("$func: Did not get metadata for $entity");
   }


   return $get;
}





#----------------------------------------------------------------------
#
# NAME:  get_entity
#
# DESC:  Get a single Entity
#
# https://rest5.bullhornstaffing.com/rest-services/abc123/
#     entity/123456/Candidate?
#     BhRestToken=74e6ae9b-b5c2-41d0-867f-f6b7a36f16db
#     fields=firstName,lastName,address,email
#
#  JSON Returned
#
# {
#   "data" : {
#     "firstName" : "Karen",
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
#     "email" : "joe@gmail.com",
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

   my $func = "get_entity";
   
   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("$func: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("$func: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("$func: entity not defined");
      return undef;
   }

   if( $fields eq "") {
      $self->add_error("$func: fields not defined");
      return undef;
   }
   
   if( $fields eq "*") {
      $self->add_error("$func: Cannot use '*' for fields");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("$func: Problem checking access token");
      return undef;
   }


   my $get = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} . qq(entity/$entity/$id) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken};
   
   $url .= "&" . qq(fields=$fields)   if $fields ne "";
   
   $self->add_debug("$func: URL = $url" . "\n");

   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};
      

   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);
      
      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $get_json = $res->content;
         
         $self->add_debug("$func: $get_json")  if $self->{debug_http};
         
         $get = $self->{json}->decode($get_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
      }
   }

   
   if( ! exists $get->{data} ) {
      $self->add_error("$func: Did not get info for $entity ($id)");
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

   my $func = "get_entity_files";
   
   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("$func: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("$func: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("$func: entity not defined");
      return undef;
   }

   if( $fields eq "") {
      $self->add_error("$func: fields not defined");
      return undef;
   }

   if( $fields eq "*") {
      $self->add_error("$func: Cannot use '*' for fields");
      return undef;
   }
   
   if( $id eq "") {
      $self->add_error("get_file: Entity ID not defined");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("$func: Problem checking access token");
      return undef;
   }

       
   my $get = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} .
       qq(entity/$entity/$id/fileAttachments) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken};

   $url .= "&" . qq(fields=$fields)   if $fields ne "";
   
   $self->add_debug("$func: URL = $url" . "\n");
   
   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);

      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $get_json = $res->content;
         
         $self->add_debug("$func: $get_json");
         
         $get = $self->{json}->decode($get_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
      }
   }

   
   if( ! exists $get->{data} ) {
      $self->add_error("$func: Did not get files for $entity ($id)");
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

   my $func = "get_file";
   
   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("$func: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("$func: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("$func: entity not defined");
      return undef;
   }

   if( $id eq "") {
      $self->add_error("$func: Entity ID not defined");
      return undef;
   }

   if( $fileid eq "") {
      $self->add_error("$func: File ID not defined");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("$func: Problem checking access token");
      return undef;
   }

       
   my $get = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} .
       qq(file/$entity/$id/$fileid) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken};

   $self->add_debug("$func: URL = $url" . "\n");
   

   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
      
      my $res = $self->{ua}->request($req);

      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $get_json = $res->content;
         
         $self->add_debug("$func: $get_json");
         
         $get = $self->{json}->decode($get_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
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
# https://rest5.bullhornstaffing.com/rest-services/abc123/
#     search/Candidate?
#     BhRestToken=74e6ae3c-b5c2-41d3-867f-f6b7a36f16ef
#     query=email:"joe@gmail.com"
#     fields=firstName,lastName,address,email
#
#  JSON Returned
#
# {
#   "total" : 1,
#   "start" : 0,
#   "count" : 1,
#   "data" : [ {
#     "firstName" : "Karen",
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
#     "email" : "joe@gmail.com",
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

   my $func = "search_entity";
   
   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("$func: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("$func: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("$func: entity not defined");
      return undef;
   }

   if( $fields eq "") {
      $self->add_error("$func: fields not defined");
      return undef;
   }

   if( $fields eq "*") {
      $self->add_error("$func: Cannot use '*' for fields");
      return undef;
   }
   
   if( $query eq "") {
      $self->add_error("$func: query not defined");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("$func: Problem checking access token");
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
   
   $self->add_debug("$func: URL = $url" . "\n") if $self->{debug_http};
   
   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;
   
   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
      
      my $res = $self->{ua}->request($req);
      
      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $search_json = $res->content;
         
         $self->add_debug("$func: $search_json") if $self->{debug_http};
         
         $search  = $self->{json}->decode($search_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
      }
   }

   
   if( ! exists $search->{total} ) {
      $self->add_error("$func: Did not get search info");
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

   my $func = "search_entity_id";
   
   my $query = qq(id:"$id") if $id ne "";

   if( $type eq "") {
      $self->add_error("$func: entity type not defined");
      return undef;
   }
   
   if( $query eq "") {
      $self->add_error("$func: query is empty");
      return undef;
   }

   if( $fields eq "") {
      $self->add_error("$func: fields not defined");
      return undef;
   }

   if( $fields eq "*") {
      $self->add_error("$func: Cannot use '*' for fields");
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

   my $func = "search_candidate_name";
   
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
      $self->add_error("$func: query is empty");
      return undef;
   }


   if( $fields eq "") {
      $self->add_error("$func: fields not defined");
      return undef;
   }

   if( $fields eq "*") {
      $self->add_error("$func: Cannot use '*' for fields");
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

   my $func = "search_candidate_email";
   
   if( $email eq "") {
      $self->add_error("$func: Email not defined");
      return 1;
   }

   my $query = qq(email:"$email");


   if( $fields eq "") {
      $self->add_error("$func: fields not defined");
      return undef;
   }
   
   if( $fields eq "*") {
      $self->add_error("$func: Cannot use '*' for fields");
      return undef;
   }

   
   return $self->search_entity("Candidate", $query, 
                               $fields, $sort, $count, $start);
}





#----------------------------------------------------------------------
#
# NAME:  query_entity
#
# DESC:  Query for an Entity
#
# https://rest5.bullhornstaffing.com/rest-services/abc123/
#     query/Candidate?
#     BhRestToken=74e6ae9b-c4c2-41d0-868e-f6b7a36f16ef
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
#     "firstName" : "Karen",
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
#     "email" : "joe@gmail.com",
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

   my $func = "query_entity";
   
   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("$func: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("$func: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("$func: entity not defined");
      return undef;
   }

   if( $where eq "") {
      $self->add_error("$func: where clause not defined");
      return undef;
   }

   if( $fields eq "") {
      $self->add_error("$func: fields not defined");
      return undef;
   }

   if( $fields eq "*") {
      $self->add_error("$func: Cannot use '*' for fields");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("$func: Problem checking access token");
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
   
   $self->add_debug("$func: URL = $url" . "\n") if $self->{debug_http};
   
   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
      
      my $res = $self->{ua}->request($req);
      
      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $query_json = $res->content;
         
         $self->add_debug("$func: $query_json") if $self->{debug_http};
         
         $query   = $self->{json}->decode($query_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
      }
   }

   
   if( ! exists $query->{count} ) {
      $self->add_error("$func: Did not get query info");
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

   my $func = "query_entity_id";
   
   my $query = qq(id=$id) if $id ne "";

   if( $type eq "") {
      $self->add_error("$func: entity type not defined");
      return undef;
   }
   
   if( $query eq "") {
      $self->add_error("$func: query is empty");
      return undef;
   }

   if( $fields eq "") {
      $self->add_error("$func: fields not defined");
      return undef;
   }

   if( $fields eq "*") {
      $self->add_error("$func: Cannot use '*' for fields");
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

   my $func = "parse_resume";
   
   if( ! -e $file ) {
      $self->add_error("$func: restUrl not defined");
      return undef;
   }

   my $format = (split /\./, File::Basename::basename($file))[1];

   if( $format eq "" ) {
      $self->add_error("$func: format not defined");
      return undef;
   }
   
   if( ! grep /^$format$/i, qw(text html pdf doc docx rtf odt) ) {
      $self->add_error("$func: format not supported");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("$func: Problem checking access token");
      return undef;
   }
      
   
   my $url = 
       $self->{login_href}->{restUrl} .
       qq(resume/parseToCandidate) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken} . "&" .
       qq(format=$format);

   $self->add_debug("$func: URL = $url" . "\n") if $self->{debug_http};

   my $req = POST $url,
       Content_Type => 'multipart/form-data',
       Content => [ file => [ $file ] ];

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};
   
   my $candidate = undef;
   
   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);

      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
   
      if($res->is_success) {
         my $candidate_json = $res->content;
         
         $self->add_debug("$func: $candidate_json")
             if $self->{debug_http};
         
         $candidate = $self->{json}->decode($candidate_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
      }
   }
   

   if( ! exists $candidate->{candidate} ) {
      $self->add_error("$func: Did not get candidate info");
   }
   
      
   return $candidate;   
}





#----------------------------------------------------------------------
#
# NAME:  create_entity
#
# DESC:  Create an Entity
#
# https://rest5.bullhornstaffing.com/rest-services/abc123/
#     entity/Candidate?
#     BhRestToken=74e6ae3b-b5c5-41d0-867f-f6b7a36f16cf
#
#  JSON Returned
#
# {
#     "changedEntityType" : "Candidate",
#     "changedEntityId"   : 123111,
#     "changeType"        : "INSERT",
#     "data" : {
#                "email" : "joe@gmail.com",
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

   my $func = "create_entity";
   
   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("$func: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("$func: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("$func: Entity not supplied");
      return undef;
   }

   if( ref $entity_href ne "HASH") {
      $self->add_error("$func: data needs to be hasf ref");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("$func: Problem checking access token");
      return undef;
   }
   

   my $create = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} . qq(entity/$entity) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken};

   $self->add_debug("$func: URL = $url" . "\n") if $self->{debug_http};
   
   my $req = HTTP::Request->new(PUT => $url);

   my $content_json = $self->{json}->pretty->encode($entity_href);
   $self->add_debug("$func: $content_json") if $self->{debug_http};
   $req->content($content_json);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};
   


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);

      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $create_json = $res->content;
         
         $self->add_debug("$func: $create_json") if $self->{debug_http};
         
         $create = $self->{json}->decode($create_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
      }
   }

   
   if( ! exists $create->{changedEntityId} ) {
      $self->add_error("$func: Did not get Entity ID back");
   }


   return $create;
}






#----------------------------------------------------------------------
#
# NAME:  update_entity
#
# DESC:  Update an Entity
#
# https://rest5.bullhornstaffing.com/rest-services/abc123/
#     entity/Candidate/121172?
#     BhRestToken=74e6ae9c-b5c2-41d3-867f-f6b7a36f16ef
#
#  JSON Returned
#
# {
#     "changedEntityType" : "Candidate",
#     "changedEntityId"   : 121172,
#     "changeType"        : "UPDATE",
#     "data" : {
#                "email" : "joe@gmail.com",
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

   my $func = "update_entity";
   
   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("$func: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("$func: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("$func: Entity not supplied");
      return undef;
   }

   if( $id eq "") {
      $self->add_error("$func: Entity ID not supplied");
      return undef;
   }
   
   if( ref $entity_href ne "HASH") {
      $self->add_error("$func: data needs to be hash ref");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("$func: Problem checking access token");
      return undef;
   }
   

   my $update = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} . qq(entity/$entity/$id) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken};

   $self->add_debug("$func: URL = $url" . "\n") if $self->{debug_http};
   
   my $req = HTTP::Request->new(POST => $url);

   my $content_json = $self->{json}->pretty->encode($entity_href);
   $self->add_debug("$func: $content_json") if $self->{debug_http};
   $req->content_type("text/plain; charset='utf8'");
   #$req->content(Encode::encode_utf8($content_json));
   $req->content($content_json);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};
   

   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
   
      my $res = $self->{ua}->request($req);

      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $update_json = $res->content;
         
         $self->add_debug("$func: $update_json") if $self->{debug_http};
         
         $update = $self->{json}->decode($update_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
      }
   }
   
   
   if( ! exists $update->{changedEntityId} ) {
      $self->add_error("$func: Did not get Entity ID back");
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
# https://rest5.bullhornstaffing.com/rest-services/abc123/
#     entity/Candidate/121172?
#     BhRestToken=74e6ae9b-b5c6-41d0-867f-f6b7a36f16ef
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

   my $func = "delete_entity";
   
   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("$func: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("$func: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "") {
      $self->add_error("$func: Entity not supplied");
      return undef;
   }

   if( $id eq "") {
      $self->add_error("$func: Entity ID not supplied");
      return undef;
   }
   

   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("$func: Problem checking access token");
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

   $self->add_debug("$func: URL = $url" . "\n") if $self->{debug_http};
   
   my $req = HTTP::Request->new(POST => $url);

   my $content_json = 
       $self->{json}->pretty->encode( { isDeleted => $undel } );

   $self->add_debug("$func: $content_json") if $self->{debug_http};
   $req->content($content_json);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};
   

   my $success = 0;
   my $tries   = 0;
   
   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);

      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
   
      if($res->is_success) {
         my $del_json = $res->content;
         
         $self->add_debug("$func: $del_json") if $self->{debug_http};
         
         $del = $self->{json}->decode($del_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
      }
   }

   
   if( ! exists $del->{changedEntityId} ) {
      $self->add_error("$func: Did not get Entity ID back");
   }


   return $del;
}






#----------------------------------------------------------------------
#
# NAME:  attach_file
#
# DESC:  Attach a file to an Entity
#
# https://rest5.bullhornstaffing.com/rest-services/abc123/
#     Candidate/<ENTITYID>?
#     BhRestToken=74e6ae9b-b7c2-41d0-827f-f6b7a36f16ef
#
#  JSON Returned
#
# {
#     "changedEntityType" : "Candidate",
#     "changedEntityId"   : 123111,
#     "changeType"        : "INSERT",
#     "data" : {
#                "email" : "joe@gmail.com",
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

   my $func = "attach_file";
   
   if( $self->{login_href}->{restUrl} eq "" ) {
      $self->add_error("$func: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "" ) {
      $self->add_error("$func: BhRestToken not defined");
      return undef;
   }

   if( $entity eq "" ) {
      $self->add_error("$func: Entity not supplied");
      return undef;
   }

   if( $entity_id eq "" ) {
      $self->add_error("$func: Entity ID not supplied");
      return undef;
   }

   if( $file eq "" ) {
      $self->add_error("$func: File not supplied");
      return undef;
   }

   if( ! -f $file ) {
      $self->add_error("$func: File not found");
      return undef;
   }

   if( $extern_id eq "" ) {
      $self->add_error("$func: External ID not supplied");
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
      $self->add_error("$func: Problem opening '$file' to get base64");
      return undef;
   }
   
   if( $f64 eq "" ) {
      $self->add_error("$func: Did not get base64 for '$file'");
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
      $self->add_error("$func: Problem checking access token");
      return undef;
   }

   
   my $attach = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} .
       qq(file/$entity/$entity_id) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken};

   $self->add_debug("$func: URL = $url" . "\n") if $self->{debug_http};
   
   my $req = HTTP::Request->new(PUT => $url);

   my $debug_json = $self->{json}->pretty->encode($f2);
   $self->add_debug("$func: $debug_json") if $self->{debug_http};
   $req->content( $self->{json}->encode($f) );

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
   
      my $res = $self->{ua}->request($req);

      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $attach_json = $res->content;
         
         $self->add_debug("$func: $attach_json") if $self->{debug_http};
         
         $attach = $self->{json}->decode($attach_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
      }
   }

   
   if( ! exists $attach->{fileId} ) {
      $self->add_error("$func: Did not get File ID back");
   }


   return $attach;
}






#----------------------------------------------------------------------
#
# NAME:  put_subscription
#
# DESC:  
#
# https://rest5.bullhornstaffing.com/rest-services/abc123/
#     event/subsciption/ABC123?
#     BhRestToken=74e6ae9b-b3c2-42d0-867f-f6b7a36f16ef
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

   my $func = "put_subscription";
   
   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("$func: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("$func: BhRestToken not defined");
      return undef;
   }

   if( $subid eq "") {
      $self->add_error("$func: subid not defined");
      return undef;
   }

   if( $type eq "") {
      $self->add_error("$func: type not defined");
      return undef;
   }

   if( $names eq "") {
      $self->add_error("$func: names not defined");
      return undef;
   }

   if( $eventTypes eq "") {
      $self->add_error("$func: eventTypes not defined");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("$func: Problem checking access token");
      return undef;
   }

   
   my $putsub = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} .
       qq(event/subscription/$subid) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken} . "&" .
       qq(type=$type)                                        . "&" .
       qq(names=$names)                                      . "&" .
       qq(eventTypes=$eventTypes);

   $self->add_debug("$func: URL = $url" . "\n")
       if $self->{debug_http};
   
   my $req = HTTP::Request->new(PUT => $url);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};


   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;
      
      my $res = $self->{ua}->request($req);
      
      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $putsub_json = $res->content;
         
         $self->add_debug("$func: $putsub_json")
             if $self->{debug_http};
         
         $putsub = $self->{json}->decode($putsub_json);

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
      }
   }
   
   
   #if( ! exists $search->{total} ) {
   #   $self->add_error("$func: Did not get search info");
   #}


   return $putsub;
}





#----------------------------------------------------------------------
#
# NAME:  get_subscription
#
# DESC:  
#
# https://rest5.bullhornstaffing.com/rest-services/abc123/
#     event/subsciption/ABC123?
#     BhRestToken=74e6de9b-b5c2-41d0-867f-f3b7a36f16ef
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
#                     'TRANSACTION_ID' =>
#                             '0e05f5b4-dbcb-4bca-b096-0c535c0e27cf'
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

   my $func = "get_subscription";
   
   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("$func: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("$func: BhRestToken not defined");
      return undef;
   }

   if( $subid eq "") {
      $self->add_error("$func: subid not defined");
      return undef;
   }

   if( $maxEvents eq "") {
      $self->add_error("$func: maxEvents not defined");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("$func: Problem checking access token");
      return undef;
   }

   
   my $getsub = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} .
       qq(event/subscription/$subid) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken} . "&" .
       qq(maxEvents=$maxEvents);

   $url .= "&" . qq(requestId=$reqid) if ($reqid ne "") || ($reqid > 0);

   
   $self->add_debug("$func: URL = $url" . "\n")
       if $self->{debug_http};
   
   my $req = HTTP::Request->new(GET => $url);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};
   

   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);

      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $getsub_json = $res->content;
         
         $self->add_debug("$func: $getsub_json")
             if $self->{debug_http};
         
         $getsub = $self->{json}->decode($getsub_json)
             if $getsub_json ne "";

         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
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
# https://rest5.bullhornstaffing.com/rest-services/abc123/
#     event/subsciption/ABC123?
#     BhRestToken=74e6ae1b-b5c2-41d4-567f-f6b7a36f16ec
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

   my $func = "delete_subscription";
   
   if( $self->{login_href}->{restUrl} eq "") {
      $self->add_error("$func: restUrl not defined");
      return undef;
   }

   if( $self->{login_href}->{BhRestToken} eq "") {
      $self->add_error("$func: BhRestToken not defined");
      return undef;
   }

   if( $subid eq "") {
      $self->add_error("$func: subid not defined");
      return undef;
   }


   # Check if the access token needs to be refreshed
   if($self->check_access_token) {
      $self->add_error("$func: Problem checking access token");
      return undef;
   }

   
   my $delsub = undef;
   
   my $url = 
       $self->{login_href}->{restUrl} .
       qq(event/subscription/$subid) . "?" .
       qq(BhRestToken=) . $self->{login_href}->{BhRestToken};

   
   $self->add_debug("$func: URL = $url" . "\n")
       if $self->{debug_http};
   
   my $req = HTTP::Request->new(DELETE => $url);

   $self->add_debug("$func: HTTP REQUEST:\n" . 
                    $req->as_string . "\n") if $self->{debug_http};

   
   my $success = 0;
   my $tries   = 0;

   # Allow multiple chances for success
   while(! $success && $tries < $self->{retry_max}) {
      $tries++;

      my $res = $self->{ua}->request($req);

      $self->add_debug("$func: HTTP RESPONSE:\n" . 
                       $res->as_string . "\n") if $self->{debug_http};
      
      if($res->is_success) {
         my $delsub_json = $res->content;
         
         $self->add_debug("$func: $delsub_json")
             if $self->{debug_http};
         
         $delsub = $self->{json}->decode($delsub_json)
             if $delsub_json ne "";
         
         $success = 1;

         # If we had to retry, write a success msg to the error log
         $self->add_error("$func: success on try $tries") if $tries > 1;
      }
      else {
         $self->process_http_error($func, $req, $res, $tries);
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
   return $_[0]->ts_epoch_to_lucene(time*1000);
}

sub ts_mysql_now {
   return $_[0]->ts_epoch_to_mysql(time*1000);
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




#----------------------------------------------------------------------
#
# NAME:  process_http_error
#
# DESC:  Process HTTP Errors
#
# ARGS:  self    Bullhorn Object
#        func    Function Name
#        req     HTTP::Request Object
#        req     HTTP::Response Object
#        tries   Number of tries attempted
#                This can be 0 if multiple attempts are not made
#
# RETN:  
#
# HIST:  
#
#----------------------------------------------------------------------
sub process_http_error {
   my ($self, $func, $req, $res, $tries) = @_;

   $self->add_error("$func: HTTP call failed");
   $self->add_error("$func: ". $res->status_line);
   $self->add_error("$func: try = $tries");

   
   # If we don't have this info in the debug log
   # add it to the error log
   if( ! $self->{debug_http} ) {
      $self->add_error("$func: HTTP REQUEST:\n" .$req->as_string."\n");
      $self->add_error("$func: HTTP RESPONSE:\n".$res->as_string."\n");
   }


   if( $tries > 0 ) {

      # Pause before trying again
      sleep $self->{retry_wait} if $tries < $self->{retry_max};


      # Check for Unauthorized in the response
      if( $res->code == 401 ) {
         $self->add_error("$func: WARNING: CHECK/REFRESH TOKEN\n");
         
      }
      # Redirection means to use a different URL     
      elsif( $res->code == 307 ) {
         $self->add_error("$func: WARNING: REDIRECTION\n");
         
      }
   }
}



#======================================================================
# END OF Bullhorn.pm
#======================================================================
1;




