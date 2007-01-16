package EasySession;
use strict;
use warnings(FATAL=>'all');

our $VERSION = '2.0.0';

#===================================
#===Module  : Framework::EasySession
#===File    : lib/Framework/EasySession.pm
#===Comment : a lib to support session
#===Require : 
#===================================

#===================================
#===Author  : qian.yu            ===
#===Email   : foolfish@cpan.org  ===
#===MSN     : qian.yu@adways.net ===
#===QQ      : 19937129           ===
#===Homepage: www.lua.cn         ===
#===================================

#=======================================
#===Author  : huang.shuai            ===
#===Email   : huang.shuai@adways.net ===
#===MSN     : huang.shuai@adways.net ===
#=======================================


#===2.0.0(2006-08-03): release, add document

our $_pkg_name=__PACKAGE__;
sub foo{1};

#===$dba: instance of EasyDBAccess
#===$rh : the hash_ref to store to database
#===$session: $rh with key _sid
#===$sid: session id ([0-9a-fA-F]{8})([0-9a-fA-F]{8})
#===$rc : affected rows 0 or 1
#===$rh_option: 
#===	now		=> unix timestamp of now
#===	expire	=> expire time after last modify
#===	ip		=> ip address (int)

#===$session=create($dba,$rh,$rh_option)
#===$session=load($dba,$sid,$rh_option)
#===$rc     =save($dba,$session,$rh_option)
#===$rc     =delete($dba , $sid|$session [,$rh_option])

our $_max_conflict=10;
our $_session_type_no_expire_no_ip=1;
our $_session_type_with_expire_with_ip=2;

#2000-01-03 +08:00 Monday 
our $_zero_time=946828800;
#one week per table
our $_inerval=86400*7;

#maybe you need edit this function
sub create_table_sql_string($$){
	$_[0]==$_session_type_with_expire_with_ip?
"
CREATE TABLE `$_[1]` (
 `RECORD_TIME` INT UNSIGNED NOT NULL ,
 `SID` INT UNSIGNED NOT NULL ,
 `DATA` BLOB NOT NULL ,
 `IP` INT UNSIGNED,
 `EXPIRE_TIME` INT UNSIGNED,
 PRIMARY KEY ( `RECORD_TIME` , `SID` ) 
) TYPE = innodb
"	:$_[0]==$_session_type_no_expire_no_ip?
"
CREATE TABLE `$_[1]` (
 `RECORD_TIME` INT UNSIGNED NOT NULL ,
 `SID` INT UNSIGNED NOT NULL ,
 `DATA` BLOB NOT NULL ,
 PRIMARY KEY ( `RECORD_TIME` , `SID` ) 
) TYPE = innodb
"	:CORE::die $_pkg_name.'::parse_string: BUG, please report it';
}

sub insert_record_sql_string($$){
	$_[0]==$_session_type_with_expire_with_ip?
"INSERT IGNORE INTO $_[1](RECORD_TIME,SID,DATA,IP,EXPIRE_TIME)VALUES(?,LAST_INSERT_ID(FLOOR(RAND()*4294967296)+1),?,?,?)"
	:$_[0]==$_session_type_no_expire_no_ip?
"INSERT IGNORE INTO $_[1](RECORD_TIME,SID,DATA)VALUES(?,LAST_INSERT_ID(FLOOR(RAND()*4294967296)+1),?)"
	:CORE::die $_pkg_name.'::parse_string: BUG, please report it';
}

sub update_record_sql_string($$){
	$_[0]==$_session_type_with_expire_with_ip?
"UPDATE $_[1] SET EXPIRE_TIME=EXPIRE_TIME-RECORD_TIME+?,DATA=? WHERE RECORD_TIME=? AND SID=? AND (EXPIRE_TIME+RECORD_TIME>=? OR EXPIRE_TIME IS NULL) AND (IP=? OR IP IS NULL OR ? IS NULL)"
	:$_[0]==$_session_type_no_expire_no_ip?
"UPDATE $_[1] SET DATA=? WHERE RECORD_TIME=? AND SID=?"
	:CORE::die $_pkg_name.'::parse_string: BUG, please report it';
}

sub select_record_sql_string($$){
	$_[0]==$_session_type_with_expire_with_ip?
"SELECT DATA,RECORD_TIME FROM $_[1] WHERE RECORD_TIME=? AND SID=? AND (EXPIRE_TIME+RECORD_TIME>=? OR EXPIRE_TIME IS NULL) AND (IP=? OR IP IS NULL OR ? IS NULL)"
	:$_[0]==$_session_type_no_expire_no_ip?
"SELECT DATA,RECORD_TIME FROM $_[1] WHERE RECORD_TIME=? AND SID=?"
	:CORE::die $_pkg_name.'::parse_string: BUG, please report it';
}

sub delete_record_sql_string($$){
	$_[0]==$_session_type_with_expire_with_ip?
"DELETE FROM $_[1] WHERE RECORD_TIME=? AND SID=?"
	:$_[0]==$_session_type_no_expire_no_ip?
"DELETE FROM $_[1] WHERE RECORD_TIME=? AND SID=?"
	:CORE::die $_pkg_name.'::parse_string: BUG, please report it';
}


#format of session id
#([0-9a-fA-F]{8})([0-9a-fA-F]{8})
#$1 is recordtime (hex encode)
#$2 id 32 bit random unsigned integer (hex encode)
sub gen_string{
	if($_[0]==$_session_type_no_expire_no_ip){
		return sprintf("%08x%08x",$_[1]+1200000000,$_[2]);
	}elsif($_[0]==$_session_type_with_expire_with_ip){
		return sprintf("%08x%08x",$_[1],$_[2]);
	}else{
		CORE::die $_pkg_name.'::parse_string: BUG, please report it';
	}
}

#decode session id
sub parse_string{
	if(defined($_[0])&&(ref($_[0]) eq '')&&($_[0]=~/^([0-9a-fA-F]{8})([0-9a-fA-F]{8})$/)){
		my $record_time=hex $1;
		if($record_time>=946641600&&$record_time<2145916800){
			return ($_session_type_with_expire_with_ip,$record_time,hex $2);
		}elsif($record_time>=2146641600&&$record_time<3345916800){
			return ($_session_type_no_expire_no_ip,$record_time-1200000000,hex $2);
		}else{
			return (undef,undef,undef);
		}
	}else{
		return (undef,undef,undef);
	}
}

#decide which table session in
sub select_table{
	my($type,$record_time)=@_;
	if($type==$_session_type_no_expire_no_ip){
		return 'SESSION_COMMON';
	}elsif($type==$_session_type_with_expire_with_ip){
		$record_time=$record_time-($record_time-$_zero_time)%$_inerval;
		local $_=($_zero_time%86400)>=12*3600?[gmtime($record_time+24*3600-$_zero_time%86400)]:[gmtime($record_time-$_zero_time%86400)];
		if(defined($_->[5])&&defined($_->[4])&&defined($_->[3])){
			return sprintf('SESSION_%04s%02s%02s',$_->[5]+1900,$_->[4]+1,$_->[3]);
		}else{
			CORE::die $_pkg_name.'::parse_string: BUG, please report it';
		}
	}else{
		CORE::die $_pkg_name.'::parse_string: BUG, please report it';
	}
}

sub create{
	my ($dba,$rh,$option)=@_;

	#===check $rh
	if(!(defined($rh)&&(ref($rh) eq 'HASH'))){
		CORE::die $_pkg_name.'::create: $2 must be a HASH';
	}

	#make a copy of $rh
	$rh={%$rh};
	
	#filter undef value
	foreach (keys %$rh){
		if($_ eq '_sid'){
			CORE::die $_pkg_name.'::create: _sid is key word';
		}elsif(defined($rh->{$_})&&(ref($rh->{$_}) eq '')){
			next;
		}elsif(!defined($rh->{$_})){
			delete $rh->{$_};
			next;
		}else{
			CORE::die $_pkg_name.'::create: $2 must be a simple HASH {string=>string,...}';
		}
	}
	my $data=pack('(L/A*)*',%$rh);
	
	if(!defined($option)){$option={};}
	my $now=$option->{now};
	if(!defined($now)){$now=CORE::time();}

	my $expire=$option->{expire};
	my $type=defined($expire)?$_session_type_with_expire_with_ip:$_session_type_no_expire_no_ip;
	
	my $ip=$option->{ip};
	my $table=select_table($type,$now);
	
	my $sid;
	my $succ=0;
	for(1..$_max_conflict){
		$dba->once();
		my ($rc,$err_code,$err_detail);
		if($type==$_session_type_with_expire_with_ip){
			($rc,$err_code,$err_detail)=$dba->execute(&insert_record_sql_string($type,$table),[$now,$data,$ip,$expire]);
		}elsif($type==$_session_type_no_expire_no_ip){
			($rc,$err_code,$err_detail)=$dba->execute(&insert_record_sql_string($type,$table),[$now,$data]);
		}else{
			CORE::die $_pkg_name.'::create: BUG, please report it';
		}

		if($err_code==0){
			if($rc==1){
				$sid=$dba->select_one('SELECT LAST_INSERT_ID();');
				$succ=1;
				last;
			}else{
				next;
			}
		}elsif($err_code==5){
			if($dba->err_code()==1146){
				$dba->execute(&create_table_sql_string($type,$table));
				next;
			}else{
				CORE::die $err_detail;
			}
		}else{
			CORE::die $err_detail;
		}
	}
	if($succ){
		$rh->{_sid}=&gen_string($type,$now,$sid);
		$rh->{_record_time}=$now;
		return $rh;
	}else{
		CORE::die $_pkg_name."::create: too much conflict";
	}
}

sub load{
	my ($dba,$_sid,$option)=@_;

	if(!(defined($_sid)&&(ref($_sid) eq ''))){
		CORE::die $_pkg_name.'::load: $2 must be a string';
	}

	my ($type,$record_time,$sid)=parse_string($_sid);
	#is _sid is not well formed,treat as no session found
	if(!defined($type)){return undef;}

	if(!defined($option)){$option={};}
	my $now=$option->{now};
	if(!defined($now)){$now=CORE::time();}
	my $ip=$option->{ip};
	my $table=select_table($type,$record_time);
	$dba->once();
	my ($rc,$err_code,$err_detail);
	if($type==$_session_type_with_expire_with_ip){
		($rc,$err_code,$err_detail)=$dba->select_row(&select_record_sql_string($type,$table),[$record_time,$sid,$now,$ip,$ip]);
	}elsif($type==$_session_type_no_expire_no_ip){
		($rc,$err_code,$err_detail)=$dba->select_row(&select_record_sql_string($type,$table),[$record_time,$sid]);
	}else{
		CORE::die $_pkg_name.'::load: BUG, please report it';
	}
	
	if($err_code==0){
		$rc={unpack('(L/A*)*',$rc->{data}),_record_time=>$rc->{record_time}};
		$rc->{_sid}=$_sid;
		return $rc;
	}elsif($err_code==1){
		return undef;
	}elsif($err_code==5){
		if($dba->err_code()==1146){
			return undef;
		}else{
			CORE::die $err_detail;
		}
	}else{
		CORE::die $err_detail;
	}
}

#if succ return 1,if fail(no row update) return 0
#if record exist, then update, else do nothing
sub save{
	my ($dba,$rh,$option)=@_;
	if(!(defined($rh)&&(ref($rh) eq 'HASH'))){
		CORE::die $_pkg_name.'::save: $2 must be a HASH';
	}
	
	my $_sid=$rh->{_sid};
	
	if(!(defined($_sid)&&(ref($_sid) eq ''))){
		CORE::die $_pkg_name.'::save: _sid needed';
	}
	
	my ($type,$record_time,$sid)=parse_string($_sid);
	if(!defined($type)){return 0;}

	if(!defined($option)){$option={};}
	my $now=$option->{now};	
	if(!defined($now)){$now=CORE::time();}
	my $ip=$option->{ip};
	
	#make a copy of $rh
	$rh={%$rh};	

	#filter undef value
	foreach (keys %$rh){
		if($_ eq '_sid'){
			delete $rh->{$_};
			next;
		}elsif($_ eq '_record_time'){
			delete $rh->{$_};
			next;
		}elsif(defined($rh->{$_})&&(ref($rh->{$_}) eq '')){
			next;
		}elsif(!defined($rh->{$_})){
			delete $rh->{$_};
			next;
		}else{
			CORE::die $_pkg_name.'::save: $2 must be a simple HASH {string=>string,...}';
		}
	}
	
	my $data=pack('(L/A*)*',%$rh);

	my $table=select_table($type,$record_time);
	$dba->once();
	my ($rc,$err_code,$err_detail);
	if($type==$_session_type_with_expire_with_ip){
		($rc,$err_code,$err_detail)=$dba->execute(&update_record_sql_string($type,$table),[$now,$data,$record_time,$sid,$now,$ip,$ip]);
	}elsif($type==$_session_type_no_expire_no_ip){
		($rc,$err_code,$err_detail)=$dba->execute(&update_record_sql_string($type,$table),[$data,$record_time,$sid]);
	}else{
		CORE::die $_pkg_name.'::load: BUG, please report it';
	}

	if($err_code==0){
		return int $rc;
	}elsif($err_code==5){
		if($dba->err_code()==1146){
			return 0;
		}else{
			CORE::die $err_detail;
		}
	}else{
		CORE::die $err_detail;
	}
}


#if succ return 1,if fail(no row delete) return 0
#if record exist, then delete, else do nothing
sub delete{
	my ($dba,$_sid)=@_;

	if(defined($_sid)&&(ref($_sid) eq 'HASH')){
		$_sid=$_sid->{_sid};
		if(defined($_sid)&&(ref($_sid) eq '')){
			#OK
		}else{
			CORE::die $_pkg_name.'::load_session: cannot got sid from $2';
		}
	}elsif(defined($_sid)&&(ref($_sid) eq '')){
		#OK	
	}else{
		CORE::die $_pkg_name.'::load_session: $2 must be a string or HASH_REF';
	}

	my ($type,$record_time,$sid)=parse_string($_sid);
	if(!defined($type)){
		return 0;
	}
	my $table=select_table($type,$record_time);
	$dba->once();
	my ($rc,$err_code,$err_detail);
	if($type==$_session_type_with_expire_with_ip){
		($rc,$err_code,$err_detail)=$dba->execute(&delete_record_sql_string($type,$table),[$record_time,$sid]);
	}elsif($type==$_session_type_no_expire_no_ip){
		($rc,$err_code,$err_detail)=$dba->execute(&delete_record_sql_string($type,$table),[$record_time,$sid]);
	}else{
		CORE::die $_pkg_name.'::load: BUG, please report it';
	}

	if($err_code==0){
		return int $rc;
	}elsif($err_code==5){
		if($dba->err_code()==1146){
			return 0;
		}else{
			CORE::die $err_detail;
		}
	}else{
		CORE::die $err_detail;
	}
}









1;

__END__


=head1 NAME

EasySession - Perl Session Interface

=head1 SYNOPSIS

  use EasySession;
  
  if(defined(&EasySession::foo)){
    print "lib is included";
  }else{
    print "lib is not included";
  }
  
	#{"_sid" => "B43b648fd431aac32", "a" => 1, "b" => 2}
	
	print EasyTool::dump(create($dba,{a=>1,b=>2,c=>undef},{expire=>300}));
	
	$dba->execute('START TRANSACTION');
	my $st=CORE::time();
	for(1..10000){
		create($dba,{a=>1,b=>2,c=>undef},{});
	}
	print CORE::time()-$st;
	$dba->execute('COMMIT');

	print EasyTool::dump(&delete($dba,{"_sid" => "43ba09e0abd5cf13", "a" => 1, "b" => 2}));
	print EasyTool::dump(&delete($dba,"43ba08a74fbe7afa"));
	print EasyTool::dump(&save($dba,{"_sid" => "43ba08a74fbe7afa", "a" => 1, "b" => 2,"c"=>3}));

I<The synopsis above only lists the major methods and parameters.>

=head1 Basic Variables and Functions
		
=head2 Variables

	$dba: instance of EasyDBAccess
	$rh : the hash_ref to store to database
	$session: $rh with key _sid
	$sid: session id ([0-9a-fA-F]{8})([0-9a-fA-F]{8})
	$rc : affected rows 0 or 1
	$rh_option: 
			now		=> unix timestamp of now
			expire	=> expire time after last modify
			ip		=> ip address (int)

=head2 Functions
		
	$session=create($dba,$rh,$rh_option);
	
	$session=load($dba,$sid,$rh_option);
	
	$rc     =save($dba,$session,$rh_option);
	#if succ return 1,if fail(no row update) return 0
	#if record exist, then update, else do nothing
	
	$rc     =delete($dba , $sid|$session [,$rh_option]);
	#if succ return 1,if fail(no row delete) return 0
	#if record exist, then delete, else do nothing

=head1 COPYRIGHT

The EasySession module is Copyright (c) 2003-2005 QIAN YU.
All rights reserved.

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.

