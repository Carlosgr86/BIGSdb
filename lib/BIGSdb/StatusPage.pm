#Written by Keith Jolley
#Copyright (c) 2020, University of Oxford
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
package BIGSdb::StatusPage;
use strict;
use warnings;
use JSON;
use 5.010;
use parent qw(BIGSdb::Page);

sub get_title {
	my ($self) = @_;
	my $desc = $self->get_db_description || 'BIGSdb';
	return "Database status: $desc";
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('ajax') ) {
		$self->_ajax;
		return;
	}
	my $desc = $self->get_db_description || 'BIGSdb';
	my $cache_string = $self->get_cache_string;
	say qq(<h1>Database status: $desc</h1>);
	say q(<div class="box" id="resultspanel">);
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		$self->_seqdef_db;
	} else {
		$self->_isolate_db;
	}
	say q(</div>);
	return;
}

sub _ajax {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	if ( ( $self->{'system'}->{'dbtype'} // q() ) eq 'sequences' ) {
		my $set_clause =
		  $set_id
		  ? ' WHERE locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE '
		  . "set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id)"
		  : q();
		my $data = $self->{'datastore'}->run_query(
			"SELECT date_entered AS label,COUNT(*) AS value FROM sequences$set_clause "
			  . 'GROUP BY date_entered ORDER BY date_entered',
			undef,
			{ fetch => 'all_arrayref', slice => {} }
		);
		say encode_json($data);
		return;
	} elsif ( ( $self->{'system'}->{'dbtype'} // q() ) eq 'isolates' ) {
		my $data = $self->{'datastore'}->run_query(
			"SELECT date_entered AS label,COUNT(*) AS value FROM $self->{'system'}->{'view'} "
			  . 'GROUP BY date_entered ORDER BY date_entered',
			undef,
			{ fetch => 'all_arrayref', slice => {} }
		);
		say encode_json($data);
		return;
	}
}

sub _seqdef_db {
	my ($self) = @_;
	my $cache_string = $self->get_cache_string;
	$self->_sequences;
	$self->_schemes;
	say q(<h2>Overview</h2>);
	say q(<ul>);
	my $scheme_data = $self->get_scheme_data( { with_pk => 1 } );
	if ( @$scheme_data == 1 ) {
		foreach (@$scheme_data) {
			my $profile_count =
			  $self->{'datastore'}
			  ->run_query( 'SELECT COUNT(*) FROM profiles WHERE scheme_id=?', $scheme_data->[0]->{'id'} );
			my $commified = BIGSdb::Utils::commify($profile_count);
			say qq(<li>Profiles ($scheme_data->[0]->{'name'}): $commified</li>);
		}
	} elsif ( @$scheme_data > 1 ) {
		say q(<li>Profiles: <a id="toggle1" class="showhide">Show</a>);
		say q(<a id="toggle2" class="hideshow">Hide</a><div class="hideshow"><ul>);
		foreach (@$scheme_data) {
			my $profile_count =
			  $self->{'datastore'}->run_query( 'SELECT COUNT(*) FROM profiles WHERE scheme_id=?', $_->{'id'} );
			my $commified = BIGSdb::Utils::commify($profile_count);
			$_->{'name'} =~ s/\&/\&amp;/gx;
			say qq(<li>$_->{'name'}: $commified</li>);
		}
		say q(</ul></div></li>);
	}
	my $history_exists = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM profile_history)');
	if ($history_exists) {
		say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;)
		  . qq(table=profile_history&amp;order=timestamp&amp;direction=descending&amp;submit=1$cache_string">)
		  . q(Profile update history</a></li>);
	}
	say q(</ul>);
	return;
}

sub _sequences {
	my ($self) = @_;
	my $allele_count = $self->_get_allele_count;
	say q(<h2>Sequences</h2>);
	my $list = [ { title => 'Total', data => BIGSdb::Utils::commify($allele_count) } ];
	my $last_update = $self->{'datastore'}->run_query('SELECT MAX(datestamp) FROM locus_stats');
	if ($last_update) {
		push @$list, { title => 'Last updated', data => $last_update };
	}
	say $self->get_list_block( $list, { width => 7 } );
	return if !$last_update;
	say q(<div id="waiting"><span class="wait_icon fas fa-sync-alt fa-spin fa-2x"></span></div>);
	say q(<div id="date_entered_container" class="embed_c3_chart" style="float:none">);
	say q(<div id="date_entered_chart"></div>);
	say q(<div id="date_entered_control"></div>);
	say q(</div>);
	return;
}

sub _schemes {
	my ($self) = @_;
	
	
}

sub _isolates {
	my ($self) = @_;
	say q(<h2>Isolates</h2>);
	my $total       = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $self->{'system'}->{'view'}");
	my $list        = [ { title => 'Total', data => BIGSdb::Utils::commify($total) } ];
	my $last_update = $self->{'datastore'}->run_query("SELECT MAX(datestamp) FROM $self->{'system'}->{'view'}");
	if ($last_update) {
		push @$list, { title => 'Last updated', data => $last_update };
	}
	say $self->get_list_block( $list, { width => 7 } );
	return if !$last_update;
	say q(<div id="waiting"><span class="wait_icon fas fa-sync-alt fa-spin fa-2x"></span></div>);
	say q(<div id="date_entered_container" class="embed_c3_chart" style="float:none">);
	say q(<div id="date_entered_chart"></div>);
	say q(<div id="date_entered_control"></div>);
	say q(</div>);
	return;
}

sub _isolate_db {
	my ($self) = @_;
	my $cache_string = $self->get_cache_string;
	$self->_isolates;
	say q(<h2>Overview</h2>);
	say q(<ul>);
	say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . q(page=fieldValues">Defined field values</a></li>);
	my $history_exists = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM isolates)');

	if ($history_exists) {
		say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;)
		  . qq(table=history&amp;order=timestamp&amp;direction=descending&amp;submit=1$cache_string">)
		  . q(Update history</a></li>);
	}
	say q(</ul>);
	return;
}

sub get_last_update {
	my ($self) = @_;
	my $tables =
	  $self->{'system'}->{'dbtype'} eq 'sequences'
	  ? [qw (locus_stats profiles profile_refs accession)]
	  : [qw (isolates isolate_aliases allele_designations allele_sequences refs)];
	my $max_date = $self->_get_max_date($tables);
	return $max_date;
}

sub _get_max_date {
	my ( $self, $tables ) = @_;
	local $" = ' UNION SELECT MAX(datestamp) FROM ';
	my $qry      = "SELECT MAX(max_datestamp) FROM (SELECT MAX(datestamp) AS max_datestamp FROM @$tables) AS v";
	my $max_date = $self->{'datastore'}->run_query($qry);
	return $max_date;
}

sub _get_allele_count {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my $set_clause =
	  $set_id
	  ? ' WHERE locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE '
	  . "set_id=$set_id)) OR locus IN (SELECT locus FROM set_loci WHERE set_id=$set_id)"
	  : q();
	return $self->{'datastore'}->run_query("SELECT SUM(allele_count) FROM locus_stats$set_clause") // 0;
}

sub initiate {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('ajax') ) {
		$self->{'type'}    = 'json';
		$self->{'noCache'} = 1;
		return;
	}
	$self->{$_} = 1 foreach qw (jQuery c3);
	return;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 0, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $url    = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=status&ajax=1";
	my $js     = << "JS";
var values;
var fields;
var date_chart;
\$(function () {
	d3.json("$url").then (function(jsonData) {
		values = ['value'];
		fields = ['date'];
		var total = 0;
		var first_date;
		var last_date;
		jsonData.forEach(function(e) {
			if (typeof first_date == 'undefined'){
				first_date = e.label;
			}
			fields.push(e.label);
			total += e.value;
			values.push(total);
			last_date = e.label;
		});
		
		date_chart = c3.generate({
			bindto: '#date_entered_chart',
			title: {
				text: "Cumulative submissions"
			},
			data: {
				x: 'date',
				columns: [
					fields,
					values
				],
				type: 'line',
				order: 'asc',
			},			
			padding: {
				right: 20
			},
			axis: {
				x: {
					type: 'timeseries',
					tick: {
                		format: '%Y-%m-%d',
                		count: 5,
                		rotate: 90,
                		fit: true 		
           			},
					height: 100
				}
			},
			legend: {
				show: false
			}
		});	
		\$("#waiting").css({display:"none"});
		display_control(first_date,last_date);
	},function(error) {
		console.log(error);
		\$("#date_entered").html('<p style="text-align:center;margin-top:5em">'
		 + '<span class="error_message">Error accessing data.</span></p>');
	});	
});	
function display_control(first_date,last_date){
	if (typeof first_date == 'undefined'){ 
		return;
	}
	var date1 = new Date(first_date);
	var date2 = new Date(last_date);
	var days = (date2.getTime() - date1.getTime()) / (1000 * 3600 * 24);
	if (days < (365 * 5)){
		return;
	}
	var dropdown = {
		365:'last year',
		730:'last 2 years',
		1825:'last 5 years'
	};
	if (days >= (365 * 10)){
		dropdown[3650] = 'last 10 years';
	}
	dropdown[days] = 'all time';
	var s = \$('<select id="date_control" />');
	for(var val in dropdown) {
    	\$('<option />', {value: val, text: dropdown[val]}).appendTo(s);
	}
	\$("#date_entered_control").html('<label for="date_control">Select date range: </label>');
	s.appendTo("#date_entered_control");
	\$("#date_control").val(days);
	\$("#date_entered_control").css({padding:"0 0 1em 1em"});
	\$("#date_control").change(function (){
		change_range(\$("#date_control").val());
	});
}
function change_range(days){
	var date = new Date();
	var min_date = new Date(date.getTime() - (days * 24 * 60 * 60 * 1000));
	var day =min_date.getDate();
	var month=min_date.getMonth()+1;
	var year=min_date.getFullYear();
	date_chart.axis.min({x: year + "-" + month + "-" + day});
}
JS
	return $js;
}
1;
