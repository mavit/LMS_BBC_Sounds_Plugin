package Plugins::BBCSounds::SessionManagement;

use warnings;
use strict;

use Slim::Networking::Async::HTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use HTTP::Request::Common;
use HTML::Entities;
use HTTP::Cookies;

use Data::Dumper;

my $log   = logger('plugin.bbcsounds');
my $prefs = preferences('plugin.bbcsounds');

sub signIn {
    my $username = shift;
    my $password = shift;    
    my $cbYes = shift;
    my $cbNo  = shift;
        
    $log->debug("++signIn");
    
    my %body = (
        jsEnabled => 'true',
        username  => $username,
        password  => $password,
        attempts  => 0
    );

    #get the session this gives us access to the cookies
    my $session = Slim::Networking::Async::HTTP->new;

    my $initrequest = HTTP::Request->new( GET => 'https://account.bbc.com' );
    $initrequest->header( 'Accept-Language' => 'en-GB,en;q=0.9' );
    $session->send_request(
        {
            request => $initrequest,
            onBody  => sub {
                my ( $http, $self ) = @_;
                my $res = $http->response;
                my $req = $http->request;
                my ($signinurl) =
                  $res->content =~ /<form\s+(?:[^>]*?\s+)?action="([^"]*)"/;
                  
                $log->debug("url $signinurl");  
                $signinurl = HTML::Entities::decode_entities($signinurl);
                my $referUrl = $req->uri;
                $signinurl = 'https://account.bbc.com' . $signinurl;

                my $request =
                  HTTP::Request::Common::POST( $signinurl, [%body] );
                $request->protocol('HTTP/1.1');
                $request->header( 'Referer' => $referUrl );
                $request->header( 'Origin'  => 'https://account.bbc.com' );
                $request->header( 'Accept-Language' => 'en-GB,en;q=0.9' );
                $request->header( 'Accept' =>
'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9'
                );
                $request->header( 'Cache-Control' => 'max-age=0' );

                $session->send_request(
                    {
                        request => $request,
                        onBody  => sub {
                            my ( $http, $self ) = @_;
                            my $res = $http->response;

                            #makes sure the cookies are persisted
                            $session->cookie_jar->save();
                            $cbYes->();
                        },
                        onRedirect => sub {
                            my ( $req, $self ) = @_;

         #try and change the method to get, as it automatically keeps it as post
                            if ( $req->method eq 'POST' ) {
                                $req->method('GET');
                            }
                        },
                        onError => sub {
                            my ( $http, $self ) = @_;
                            my $res = $http->response;
                            $log->debug(
                                'Error status - ' . $res->status_line );
                            $cbNo->();
                        }
                    }
                );

            },
            onError =>

              # Called when no response was received or an error occurred.
              sub {
                $log->warn("error: $_[1]");
                $cbNo->();
              }
        }
    );
    $log->debug("--signIn");
    return;
}

sub isSignedIn {
    $log->debug("++isSignedIn");
    my $session   = Slim::Networking::Async::HTTP->new;
    my $cookiejar = $session->cookie_jar;
    my $key       = $cookiejar->{COOKIES}->{'.bbc.co.uk'}->{'/'}->{'ckns_id'};
    if ( defined $key ) {
        my $cookieepoch = @{$key}[5];
        if (defined $cookieepoch) {
			my $epoch       = time();        
			if ( $epoch < $cookieepoch ) {
				$log->debug("--isSignedIn - true");
				return 1;
			}
			else
			{
				$log->debug("--isSignedIn - false");
				return;        
			}
		}        
		else
		{
			$log->debug("--isSignedIn - false");
			return;        
		}	
    }
    else {
        $log->debug("--_isSignedIn - false");
        return;
    }
}

sub signOut {
    my $cbYes = shift;
    my $cbNo  = shift;
    $log->debug("++signOut");
    my $session = Slim::Networking::Async::HTTP->new;
    my $sessionrequest =
      HTTP::Request->new( GET => 'https://session.bbc.com/session/signout?ptrt=https%3A%2F%2Faccount.bbc.com%2Fsignout&switchTld=1' );
      
    $session->send_request(
        {
            request => $sessionrequest,
            onBody  => sub {
                my ( $http, $self ) = @_;
                $session->cookie_jar->save();
                $cbYes->();
                $log->debug("--signOut");
                return;
            },
            onError => sub {
                my ( $http, $self ) = @_;
                my $res = $http->response;
                $log->debug( 'Error status - ' . $res->status_line );
                $cbNo->();
                $log->debug("--signOut");
                return;
            }
        }
    );
}

sub renewSession {
    $log->debug("++renewSession");
    my $cbYes = shift;
    my $cbNo  = shift;

    if (isSignedIn) {
        if ( _hasSession() ) {
            $cbYes->();
            $log->debug("--renewSession");
            return;
        }
        else {
            my $session = Slim::Networking::Async::HTTP->new;
            my $sessionrequest =
              HTTP::Request->new( GET =>
'https://session.bbc.co.uk/session?context=iplayerradio&userOrigin=sounds'
              );
            $session->send_request(
                {
                    request => $sessionrequest,
                    onBody  => sub {
                        my ( $http, $self ) = @_;
                        $session->cookie_jar->save();
                        if ( _hasSession() ) {
                            $cbYes->();
                            $log->debug("--renewSession");
                            return;
                        }
                        else {
                            $cbNo->();
                            $log->debug("--renewSession");
                            return;
                        }
                    },
                    onError => sub {
                        my ( $http, $self ) = @_;
                        my $res = $http->response;
                        $log->debug( 'Error status - ' . $res->status_line );
                        $cbNo->();
                        $log->debug("--renewSession");
                        return;
                    }
                }
            );
        }
    }
    else {
        $cbNo->();
        $log->debug("--renewSession");
        return;
    }
}

sub _hasSession {
    $log->debug("++_hasSession");
    my $session   = Slim::Networking::Async::HTTP->new;
    my $cookiejar = $session->cookie_jar;
    my $key       = $cookiejar->{COOKIES}->{'.bbc.co.uk'}->{'/'}->{'ckns_atkn'};
    if ( defined $key ) {
        my $cookieepoch = @{$key}[5];
        my $epoch       = time();

        if ( $epoch < $cookieepoch ) {
            $log->debug("--_hasSession - true");
            return 1;
        }
        else {
            $log->debug("--_hasSession - false");
            return;
        }

    }
    else {
        $log->debug("--_hasSession - false");
        return;
    }
}
1;

