#Written by Keith Jolley
#(c) 2010-2015, University of Oxford
#E-mail: keith.jolley@zoo.ox.ac.uk
#
#This file is part of Bacterial Isolate Genome Sequence Database (BIGSdb).
#
#BIGSdb is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#BIGSdb is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
#
#perl-md5-login used as basis.  Extensively modified for BIGSdb.
#Javascript md5 now provided by CryptoJS (code.google.com/p/crypto-js)
#as a separate file.
#
#Copyright for perl-md5-login is below.
########################################################################
#
# perl-md5-login: a Perl/CGI + JavaScript user authorization
#
# This software is provided 'as-is' and without warranty. Use it at
# your own risk.
#
# SourceForge project: http://perl-md5-login.sourceforge.net/
#
# Perl/CGI interface Copyright 2003 Alan Raetz <alanraetz@chicodigital.com>
# Released under the LGPL license (see http://www.fsf.org)
#
# The original Digest::MD5 Perl Module interface was written by
# Neil Winton <N.Winton@axion.bt.co.uk> and is maintained by
# Gisle Aas <gisle@ActiveState.com>
#
package BIGSdb::Login;
use Digest::MD5;
use strict;
use warnings;
use 5.010;
use Log::Log4perl qw(get_logger);
use parent qw(BIGSdb::Page);
use List::MoreUtils qw(any);
my $logger = get_logger('BIGSdb.Application_Authentication');
use constant UNIQUE_STRING => 'bigsdbJolley';
############################################################################
#
# Cookie and session timeout parameters, default is 1 day
#
use constant COOKIE_TIMEOUT  => '+12h';          
use constant SESSION_TIMEOUT => 12 * 60 * 60;    #Should be the same as cookie timeout (in seconds)

# When a CGI response is received, the sessionID
# is used to retrieve the time of the request. If the sessionID
# does not index a timestamp, or if the timestamp is older than
# screen_timeout, the password login fails and exits.
use constant LOGIN_TIMEOUT => 600;

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} = { general => 0, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub print_content {
	my ($self) = @_;
	print "<h1>Please log in";
	print " - $self->{'system'}->{'description'} database" if $self->{'system'}->{'description'};
	print "</h1>";
	$self->print_banner;
	if ( $self->{'authenticate_error'} ) {
		say qq(<div class="box" id="statusbad"><p>$self->{'authenticate_error'}</p></div>);
	}
	$self->_print_entry_form;
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Log in - $desc";
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery noCache CryptoJS.MD5);

	# Cookies reference and verify a matching IP address
	my $ip_addr = $ENV{'REMOTE_ADDR'};
	$ip_addr =~ s/\.\d+$//;

	#don't use last part of IP address - due to problems with load-balancing proxies
	$self->{'ip_addr'} = $ip_addr;

	#Create per database cookies to prevent problems when opening two sessions with
	#different credentials.
	$self->{'session_cookie'} = "$self->{'system'}->{'db'}_session";
	$self->{'pass_cookie'}    = "$self->{'system'}->{'db'}_auth";
	$self->{'user_cookie'}    = "$self->{'system'}->{'db'}_user";

	# Each CGI call has its own seed, using Perl's built-in seed generator.
	# This is psuedo-random, but only controls the sessionID value, which
	# is also hashed with the ip address and your UNIQUE_STRING
	$self->{'random_number'} = int( rand(4294967296) );
	return;
}

sub secure_login {
	( my $self ) = @_;
	my ( $user, $password_hash ) = $self->_MD5_login;
	######################################################
	# If they've gotten to this point, they have been
	# authorized against the database (they
	# correctly filled in the name/password field)
	# so store their current IP address in the database
	######################################################
	$self->_set_current_user_IP_address( $user, $self->{'ip_addr'} );
	######################################################
	# Set Cookie information with a session timeout
	######################################################
	my $setCookieString = Digest::MD5::md5_hex( $self->{'ip_addr'} . $password_hash . UNIQUE_STRING );
	my @cookies         = (
		$self->{'session_cookie'} => $self->{'vars'}->{'session'},
		$self->{'pass_cookie'}    => $setCookieString,
		$self->{'user_cookie'}    => $user
	);
	$self->_create_session( $self->{'vars'}->{'session'}, 'active', $user );
	my $cookies_ref = $self->_set_cookies( \@cookies, COOKIE_TIMEOUT );
	return ( $user, $cookies_ref );    # SUCCESS, w/cookie header
}

sub login_from_cookie {
	( my $self ) = @_;
	throw BIGSdb::AuthenticationException("No valid session") if $self->{'logged_out'};
	$self->_timout_sessions;
	my %cookies = $self->_get_cookies( $self->{'session_cookie'}, $self->{'pass_cookie'}, $self->{'user_cookie'} );
	foreach ( keys %cookies ) {
		$logger->debug("cookie $_ = $cookies{$_}") if defined $cookies{$_};
	}
	my $saved_password_hash = $self->get_password_hash( $cookies{ $self->{'user_cookie'} } ) || '';
	my $saved_IP_address    = $self->_get_IP_address( $cookies{ $self->{'user_cookie'} } );
	my $cookie_string       = Digest::MD5::md5_hex( $self->{'ip_addr'} . $saved_password_hash . UNIQUE_STRING );
	##############################################################
	# Test the cookies against the current database
	##############################################################
	# If the current IP address matches the saved IP address
	# and the current cookie hash matches the saved cookie hash
	# we allow access.
	##############################################################
	if (   $saved_password_hash
		&& ( $saved_IP_address // '' ) eq $self->{'ip_addr'}
		&& ( $cookies{ $self->{'pass_cookie'} } // '' ) eq $cookie_string
		&& $self->_active_session_exists( $cookies{ $self->{'session_cookie'} }, $cookies{ $self->{'user_cookie'} } ) )
	{
		$logger->debug("User cookie validated, allowing access.");

		# good cookie, allow access
		return $cookies{ $self->{'user_cookie'} };
	}
	$cookies{ $self->{'pass_cookie'} } ||= '';
	$logger->debug("Cookie not validated. cookie:$cookies{$self->{'pass_cookie'}} string:$cookie_string");
	throw BIGSdb::AuthenticationException("No valid session");
}

sub _MD5_login {
	my ($self) = @_;
	$self->_timout_logins;    # remove entries older than current_time + $timeout
	if ( $self->{'vars'}->{'submit'} ) {
		if ( my $password_hash = $self->_check_password ) {
			$logger->info("User $self->{'vars'}->{'user'} logged in to $self->{'instance'}.");
			$self->_delete_session( $self->{'cgi'}->param('session') );
			return ( $self->{'vars'}->{'user'}, $password_hash );    # return user name and password hash
		}
	}

	# This sessionID will be valid for only LOGIN_TIMEOUT seconds
	$self->print_page_content;
	throw BIGSdb::AuthenticationException;
}
####################  END OF MAIN PROGRAM  #######################
sub _check_password {
	my ($self) = @_;
	if ( !$self->{'vars'}->{'user'} )     { $self->_error_exit("The name field was missing.") }
	if ( !$self->{'vars'}->{'password'} ) { $self->_error_exit("The password field was missing.") }
	my $login_session_exists = $self->_login_session_exists( $self->{'vars'}->{'session'} );
	if ( !$login_session_exists ) { $self->_error_exit("The login window has expired - please resubmit credentials.") }
	my $saved_password_hash = $self->get_password_hash( $self->{'vars'}->{'user'} ) || '';
	my $hashedPassSession = Digest::MD5::md5_hex( $saved_password_hash . $self->{'vars'}->{'session'} );
	$logger->debug("using session ID = $self->{'vars'}->{'session'}");
	$logger->debug("Saved password hash for $self->{'vars'}->{'user'} = $saved_password_hash");
	$logger->debug("Submitted password hash for $self->{'vars'}->{'user'} = $self->{'vars'}->{'password'}");
	$logger->debug("hashed stored pass + session string = $hashedPassSession");
	$logger->debug("hashed submitted pass + session string = $self->{'vars'}->{'hash'}");

	# Compare the calculated hash based on the saved password to
	# the hash returned by the CGI form submission: they must match
	if ( $hashedPassSession ne $self->{'vars'}->{'hash'} ) {
		$self->_delete_session( $self->{'cgi'}->param('session') );
		$self->_error_exit("Invalid username or password entered.  Please try again.");
	} else {
		return $saved_password_hash;
	}
	return;
}

sub _print_entry_form {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	$self->{'sessionID'} = Digest::MD5::md5_hex( $self->{'ip_addr'} . $self->{'random_number'} . UNIQUE_STRING );
	if ( !$q->param('session') || !$self->_login_session_exists( $q->param('session') ) ) {
		$self->_create_session( $self->{'sessionID'}, 'login', undef );
	}
	say qq(<div class="box" id="queryform">);
	my $reg_file = "$self->{'dbase_config_dir'}/$self->{'instance'}/registration.html";
	$self->print_file($reg_file) if -e $reg_file;
	say <<"HTML";
<p>Please enter your log-in details.  Part of your IP address is used along with your username to set up your session. 
If you have a session opened on a different computer, where the first three parts of the IP address vary, it will be 
closed when you log in here. </p>
<noscript><p class="highlight">Please note that Javascript must be enabled in order to login.  Passwords are encrypted 
using Javascript prior to transmitting to the server.</p></noscript>
HTML
	say $q->start_form( -onSubmit => "password.value=password_field.value; password_field.value=''; "
		  . "password.value=CryptoJS.MD5(password.value+user.value); hash.value=CryptoJS.MD5(password.value+session.value); return true" );
	say qq(<fieldset style="float:left"><legend>Log in details</legend>);
	say qq(<ul><li><label for="user" class="display">Username: </label>);
	say $q->textfield( -name => 'user', -id => 'user', -size => 20, -maxlength => 20, -style => 'width:12em' );
	say qq(</li><li><label for="password_field" class="display">Password: </label>);
	say $q->password_field( -name => 'password_field', -id => 'password_field', -size => 20, -maxlength => 20, -style => 'width:12em' );
	say '</li></ul></fieldset>';
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Log in' } );
	$q->param( session  => $self->{'sessionID'} );
	$q->param( hash     => '' );
	$q->param( password => '' );

	#Pass all parameters in case page has timed out from an internal page
	my @params = $q->param;
	foreach my $param (@params) {
		next if any { $param eq $_ } qw(password_field user submit);
		say $q->hidden($param);
	}
	say $q->end_form;
	say "</div>";
	return;
}

sub _error_exit {
	my ( $self, $msg ) = @_;
	$self->{'cgi'}->param( 'password', '' );
	$self->{'authenticate_error'} = $msg;
	$self->print_page_content;
	throw BIGSdb::AuthenticationException($msg);
}
#############################################################################
# Authentication Database Code
#############################################################################
sub _active_session_exists {
	my ( $self, $session, $username ) = @_;
	return $self->{'datastore'}->run_query(
		"SELECT EXISTS(SELECT * FROM sessions WHERE (dbase,session,state,username)=(?,?,?,?))",
		[ $self->{'system'}->{'db'}, $session, 'active', $username ],
		{ db => $self->{'auth_db'}, cache => 'Login::active_session_exists' }
	);
}

sub _login_session_exists {
	my ( $self, $session ) = @_;
	return $self->{'datastore'}->run_query(
		"SELECT EXISTS(SELECT * FROM sessions WHERE (dbase,session,state)=(?,?,?))",
		[ $self->{'system'}->{'db'}, $session, 'login' ],
		{ db => $self->{'auth_db'}, cache => 'Login::login_session_exists' }
	);
}

sub get_password_hash {
	my ( $self, $name ) = @_;
	return if !$name;
	my $password = $self->{'datastore'}->run_query(
		"SELECT password FROM users WHERE dbase=? AND name=?",
		[ $self->{'system'}->{'db'}, $name ],
		{ db => $self->{'auth_db'} }
	);
	return $password;
}

sub set_password_hash {
	my ( $self, $name, $hash ) = @_;
	return if !$name;
	my $exists = $self->{'datastore'}->run_query(
		"SELECT EXISTS(SELECT * FROM users WHERE dbase=? AND name=?)",
		[ $self->{'system'}->{'db'}, $name ],
		{ db => $self->{'auth_db'} }
	);
	my $qry;
	if ( !$exists ) {
		$qry = "INSERT INTO users (password,dbase,name) VALUES (?,?,?)";
	} else {
		$qry = "UPDATE users SET password=? WHERE dbase=? AND name=?";
	}
	my $sql = $self->{'auth_db'}->prepare($qry);
	eval { $sql->execute( $hash, $self->{'system'}->{'db'}, $name ); };
	if ($@) {
		$logger->error($@);
		$self->{'auth_db'}->rollback;
		return 0;
	} else {
		$self->{'auth_db'}->commit;
		return 1;
	}
}

sub _get_IP_address {
	my ( $self, $name ) = @_;
	return if !$name;
	my $ip_address = $self->{'datastore'}->run_query(
		"SELECT ip_address FROM users WHERE dbase=? AND name=?",
		[ $self->{'system'}->{'db'}, $name ],
		{ db => $self->{'auth_db'} }
	);
	return $ip_address;
}

sub _set_current_user_IP_address {
	my ( $self, $userName, $ip_address ) = @_;
	my $sql = $self->{'auth_db'}->prepare("UPDATE users SET ip_address=? WHERE dbase=? AND name=?");
	eval { $sql->execute( $ip_address, $self->{'system'}->{'db'}, $userName ); };
	if ($@) {
		$logger->error($@);
		$self->{'auth_db'}->rollback;
	} else {
		$logger->debug("Set IP address for $userName: $ip_address");
		$self->{'auth_db'}->commit;
	}
	return;
}

sub _create_session {
	my ( $self, $session, $state, $username ) = @_;
	my $exists = $self->{'datastore'}->run_query(
		"SELECT EXISTS(SELECT * FROM sessions WHERE dbase=? AND session=?)",
		[ $self->{'system'}->{'db'}, $session ],
		{ db => $self->{'auth_db'} }
	);
	return if $exists;
	my $sql = $self->{'auth_db'}->prepare("INSERT INTO sessions (dbase,session,start_time,state,username) VALUES (?,?,?,?,?)");
	eval { $sql->execute( $self->{'system'}->{'db'}, $session, time, $state, $username ) };
	if ($@) {
		$logger->error($@);
		$self->{'auth_db'}->rollback;
	} else {
		$logger->debug("$state session created: $session");
		$self->{'auth_db'}->commit;
	}
	return;
}

sub _delete_session {
	my ( $self, $session_id ) = @_;
	eval { $self->{'auth_db'}->do( "DELETE FROM sessions WHERE session=?", undef, $session_id ); };
	if ($@) {
		$logger->error($@);
		$self->{'auth_db'}->rollback;
	} else {
		$self->{'auth_db'}->commit;
	}
	return;
}

sub _timout_sessions {

	#Do this for all databases and for both login and active sessions since active session timeout is longer than login timeout.
	my ($self) = @_;
	eval { $self->{'auth_db'}->do( "DELETE FROM sessions WHERE start_time<?", undef, ( time - SESSION_TIMEOUT ) ); };
	if ($@) {
		$logger->error($@);
		$self->{'auth_db'}->rollback;
	} else {
		$self->{'auth_db'}->commit;
	}
	return;
}

sub _timout_logins {

	#Do this for all databases
	my ($self) = @_;
	eval { $self->{'auth_db'}->do( "DELETE FROM sessions WHERE start_time<? AND state=?", undef, ( time - LOGIN_TIMEOUT ), 'login' ); };
	if ($@) {
		$logger->error($@);
		$self->{'auth_db'}->rollback;
	} else {
		$self->{'auth_db'}->commit;
	}
	return;
}
#############################################################################
# Cookies Code
#############################################################################
sub logout {
	my ($self) = @_;
	my %cookies = $self->_get_cookies( $self->{'session_cookie'}, $self->{'user_cookie'} );
	$logger->info("User $cookies{$self->{'user_cookie'}} logged out of $self->{'instance'}.") if $cookies{ $self->{'user_cookie'} };
	$self->_delete_session( $cookies{ $self->{'session_cookie'} } );
	my $cookies_ref = $self->_clear_cookies( $self->{'session_cookie'}, $self->{'pass_cookie'}, $self->{'user_cookie'} );
	$self->{'logged_out'} = 1;
	return $cookies_ref;
}

sub _get_cookies {
	my ( $self, @cookie_list ) = @_;
	my $query = $self->{'cgi'};
	my %cookies;
	foreach my $name (@cookie_list) {
		$cookies{$name} = $query->cookie($name);
	}
	return %cookies;
}

sub _clear_cookies {
	my ( $self, @entries ) = @_;
	my @cookies;
	foreach my $entry (@entries) {
		push( @cookies, $entry );
		push( @cookies, 'x' );
	}
	return $self->_set_cookies( [@cookies], '+0s' );
}

sub _set_cookies {
	my ( $self, $cookie_ref, $expires ) = @_;
	my @cookie_objects;
	my $query = CGI->new;
	while ( my ( $cookie, $value ) = _shift2($cookie_ref) ) {
		push( @cookie_objects, $self->_make_cookie( $query, $cookie, $value, $expires ) );
	}
	return \@cookie_objects;
}

sub _shift2 {
	my ($cookie_ref) = @_;
	return splice( @$cookie_ref, 0, 2 );
}

sub _make_cookie {
	my ( $self, $query, $cookie, $value, $expires ) = @_;
	return $query->cookie( -name => $cookie, -value => $value, -expires => $expires, -path => '/', );
}
1;
