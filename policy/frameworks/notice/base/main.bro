##! This is the notice framework which enables Bro to "notice" things which
##! are odd or potentially bad.  Decisions of the meaning of various notices
##! need to be done per site because Bro does not ship with assumptions about
##! what is bad activity for sites.  More extensive documetation about using
##! the notice framework can be found in the documentation section of the
##! http://www.bro-ids.org/ website.

module Notice;

export {
	redef enum Log::ID += { 
		## This is the primary logging stream for notices.  It must always be
		## referenced with the module name included because the name is 
		## also used by the global function :bro:id:`NOTICE`.
		NOTICE, 
		## This is the notice policy auditing log.  It records what the current
		## notice policy is at Bro init time.
		NOTICE_POLICY,
		## This is the alarm stream.
		ALARM,
	};

	## Scripts creating new notices need to redef this enum to add their own 
	## specific notice types which would then get used when they call the
	## :bro:id:`NOTICE` function.  The convention is to give a general category
	## along with the specific notice separating words with underscores and using
	## leading capitals on each word except for abbreviations which are kept in
	## all capitals.  For example, SSH::Login is for heuristically guessed 
	## successful SSH logins.
	type Type: enum {
		## Notice reporting a count of how often a notice occurred.
		Tally,
	};
	
	## These are values representing actions that can be taken with notices.
	type Action: enum {
		## Indicates that there is no action to be taken.
		ACTION_NONE,
		## Indicates that the notice should be sent to the notice logging stream.
		ACTION_LOG,
		## Indicates that the notice should be sent to the email address(es) 
		## configured in the :bro:id:`Notice::mail_dest` variable.
		ACTION_EMAIL,
		## Indicates that the notice should be alarmed.
		ACTION_ALARM,
	};
	
	type Info: record {
		ts:             time           &log &optional;
		uid:            string         &log &optional;
		id:             conn_id        &log &optional;
		
		## These are shorthand ways of giving the uid and id to a notice.  The
		## reference to the actual connection will be deleted after applying
		## the notice policy.
		conn:           connection     &optional;
		iconn:          icmp_conn      &optional;
		
		## The :bro:enum:`Notice::Type` of the notice.
		note:           Type           &log;
		## The human readable message for the notice.
		msg:            string         &log &optional;
		## The human readable sub-message.
		sub:            string         &log &optional;
		
		## Source address, if we don't have a :bro:type:`conn_id`.
		src:            addr           &log &optional;
		## Destination address.
		dst:            addr           &log &optional;
		## Associated port, if we don't have a :bro:type:`conn_id`.
		p:              port           &log &optional;
		## Associated count, or perhaps a status code.
		n:              count          &log &optional;
		
		## Peer that raised this notice.
		src_peer:       event_peer     &optional;
		## Textual description for the peer that raised this notice.
		peer_descr:     string         &log &optional;
		
		## The actions that are to be applied to this notice.  The set[count] 
		## is to indicate which :bro:id:`Notice::policy` items
		## triggered the action being added to the notice.
		actions:        set[Notice::Action] &log &optional;
		
		## These are policy items that returned T and applied their action
		## to the notice.
		## TODO: this can't take set() as a default. (bug)
		policy_items:   set[count]     &log &optional;
		
		## By adding chunks of text into this element, other scripts can
		## expand on notices that are being emailed.  The normal way to add text
		## is to extend the vector by handling the :bro:id:`Notice::notice`
		## event and modifying the notice in place.  For newline characters
		## to be rendered properly, they must be escaped as "\\n".
		email_body_sections:  vector of string &default=vector();
	};
	
	## Ignored notice types.
	const ignored_types: set[Notice::Type] = {} &redef;
	## Emailed notice types.
	const emailed_types: set[Notice::Type] = {} &redef;
	## Alarmed notice types.
	const alarmed_types: set[Notice::Type] = {} &redef;
	
	## This is the record that defines the items that make up the notice policy.
	type PolicyItem: record {
		## This is the exact positional order in which the :id:type:`PolicyItem`
		## records are checked.  This is set internally by the notice framework.
		position: count                            &log &optional;
		## Define the priority for this check.  Items are checked in ordered
		## from highest value (10) to lowest value (0).
		priority: count                            &log &default=5;
		## An action given to the notice if the predicate return true.
		result:   Notice::Action                   &log &default=ACTION_NONE;
		## The pred (predicate) field is a function that returns a boolean T 
		## or F value.  If the predicate function return true, the action in 
		## this record is applied to the notice that is given as an argument 
		## to the predicate function.
		pred:     function(n: Notice::Info): bool;
		## Indicates this item should terminate policy processing if the 
		## predicate returns T.
		halt:     bool                             &log &default=F;
	};
	
	## This is the where the :bro:id:`Notice::policy` is defined.  All notice
	## processing is done through this variable.
	const policy: set[PolicyItem] = {
		[$pred(n: Notice::Info) = { return (n$note in Notice::ignored_types); },
		 $halt=T, $priority = 9],
		[$pred(n: Notice::Info) = { return (n$note in Notice::alarmed_types); },
		 $priority = 8],
		[$pred(n: Notice::Info) = { return (n$note in Notice::emailed_types); },
		 $result = ACTION_EMAIL,
		 $priority = 8],
		[$pred(n: Notice::Info) = { return T; },
		 $result = ACTION_LOG,
		 $priority = 0],
	} &redef;
	
	## Local system sendmail program.
	const sendmail            = "/usr/sbin/sendmail" &redef;
	## Local system echo/printf program that supports interpretted character
	## sequences (e.g. "\n"), for use in with conjunction with sendmail.
	const echocmd             = "echo -e" &redef;
	## Email address to send notices with the :bro:enum:`ACTION_EMAIL` action.
	const mail_dest           = ""                   &redef;
	
	## Address that emails will be from.
	const mail_from           = "Big Brother <bro@localhost>" &redef;
	## Reply-to address used in outbound email.
	const reply_to            = "" &redef;
	## Text string prefixed to the subject of all emails sent out.
	const mail_subject_prefix = "[Bro]" &redef;

	## This is the event that is called as the entry point to the 
	## notice framework by the global :bro:id:`NOTICE` function.  By the time 
	## this event is generated, default values have already been filled out in
	## the :bro:type:`Notice::Info` record and synchronous functions in the 
	## :bro:id:`Notice:sync_functions` have already been called.  The notice
	## policy has also been applied.
	global notice: event(n: Info);

	## This is a set of functions that provide a synchronous way for scripts 
	## extending the notice framework to run before the normal event based
	## notice pathway that most of the notice framework takes.  This is helpful
	## in cases where an action against a notice needs to happen immediately
	## and can't wait the short time for the event to bubble up to the top of
	## the event queue.  An example is the IP address dropping script that 
	## can block IP addresses that have notices generated because it 
	## needs to operate closer to real time than the event queue allows it to.
	## Normally the event based extension model using the 
	## :bro:id:`Notice::notice` event will work fine if there aren't harder
	## real time constraints.
	const sync_functions: set[function(n: Notice::Info)] = set() &redef;
	
	## Call this function to send a notice in an email.  It is already used
	## by default with the built in :bro:enum:`ACTION_EMAIL` and
	## :bro:enum:`ACTION_PAGE` actions.
	global email_notice_to: function(n: Info, dest: string, extend: bool);
	
	## This is an internally used function, please ignore it.  It's only used
	## for filling out missing details of :bro:type:`Notice:Info` records
	## before the synchronous and asynchronous event pathways have begun.
	global apply_policy: function(n: Notice::Info);
	
	## This event can be handled to access the :bro:type:`Info`
	## record as it is sent on to the logging framework.
	global log_notice: event(rec: Info);
}

# This is an internal variable used to store the notice policy ordered by
# priority.
global ordered_policy: vector of PolicyItem = vector();

event bro_init()
	{
	Log::create_stream(NOTICE_POLICY, [$columns=PolicyItem]);
	Log::create_stream(Notice::NOTICE, [$columns=Info, $ev=log_notice]);
	
	Log::create_stream(ALARM, [$columns=Notice::Info]);
	# Make sure that this log is output as text so that it can be packaged
	# up and emailed later.
	Log::add_filter(ALARM, [$name="default", $writer=Log::WRITER_ASCII]);
	}
	# TODO: need a way to call a Bro script level callback during file rotation.
	#       we need more than a just $postprocessor.
	#redef Log::rotation_control += {
	#	[Log::WRITER_ASCII, "alarm"] = [$postprocessor="mail-alarms"];
	#};

# TODO: fix this.
#function notice_tags(n: Notice::Info) : table[string] of string
#	{
#	local tgs: table[string] of string = table();
#	if ( is_remote_event() )
#		{
#		if ( n$src_peer$descr != "" )
#			tgs["es"] = n$src_peer$descr;
#		else
#			tgs["es"] = fmt("%s/%s", n$src_peer$host, n$src_peer$p);
#		}
#	else
#		{
#		tgs["es"] = peer_description;
#		}
#	return tgs;
#	}

function email_notice_to(n: Notice::Info, dest: string, extend: bool)
	{
	if ( reading_traces() || dest == "" )
		return;
		
	local email_text = cat(
		"From: ", mail_from, "\\n",
		"Subject: ", mail_subject_prefix, " ", n$note, "\\n",
		"To: ", dest, "\\n",
		# TODO: BiF to get version (the resource_usage Bif seems like overkill).
		"User-Agent: Bro-IDS/?.?.?\\n");
	
	if ( reply_to != "" )
		email_text = cat(email_text, "Reply-To: ", reply_to, "\\n");
	
	# The notice emails always start off with the human readable message.
	email_text = cat(email_text, "\\n", n$msg, "\\n");
	
	# Add the extended information if it's requested.
	if ( extend )
		{
		for ( i in n$email_body_sections )
			{
			email_text = cat(email_text, "******************\\n");
			email_text = cat(email_text, n$email_body_sections[i], "\\n");
			}
		}
	
	email_text = cat(email_text, "\\n\\n--\\n[Automatically generated]\\n\\n");
	
	local mail_cmd =
		fmt("%s \"%s\" | %s -t -oi",
			echocmd, str_shell_escape(email_text), sendmail);
	system(mail_cmd);
	}

event notice(n: Notice::Info) &priority=-5
	{
	if ( ACTION_EMAIL in n$actions )
		email_notice_to(n, mail_dest, T);
	if ( ACTION_LOG in n$actions )
		Log::write(Notice::NOTICE, n);
	if ( ACTION_ALARM in n$actions )
		Log::write(ALARM, n);
	}

# Executes a script with all of the notice fields put into the
# new process' environment as "BRO_ARG_<field>" variables.
function execute_with_notice(cmd: string, n: Notice::Info)
	{
	# TODO: fix system calls
	#local tgs = tags(n);
	#system_env(cmd, tags);
	}
	
# This is run synchronously as a function before all of the other 
# notice related functions and events.  It also modifies the 
# :bro:type:`Notice::Info` record in place.
function apply_policy(n: Notice::Info)
	{
	# Fill in some defaults.
	if ( ! n?$ts )
		n$ts = network_time();

	if ( n?$conn )
		{
		if ( ! n?$id )
			n$id = n$conn$id;
		if ( ! n?$uid )
			n$uid = n$conn$uid;
		}
	
	if ( n?$id )
		{
		if ( ! n?$src  )
			n$src = n$id$orig_h;
		if ( ! n?$dst )
			n$dst = n$id$resp_h;
		if ( ! n?$p )
			n$p = n$id$resp_p;
		}

	if ( n?$iconn )
		{
		if ( ! n?$src )
			n$src = n$iconn$orig_h;
		if ( ! n?$dst )
			n$dst = n$iconn$resp_h;
		}

	if ( ! n?$src_peer )
		n$src_peer = get_event_peer();
	n$peer_descr = n$src_peer?$descr ? n$src_peer$descr : fmt("%s", n$src_peer$host);
	
	if ( ! n?$actions )
		n$actions = set();
	
	if ( ! n?$policy_items )
		n$policy_items = set();
	
	for ( i in ordered_policy )
		{
		if ( ordered_policy[i]$pred(n) )
			{
			add n$actions[ordered_policy[i]$result];
			add n$policy_items[int_to_count(i)];
			
			# If the policy item wants to halt policy processing, do it now!
			if ( ordered_policy[i]$halt )
				break;
			}
		}
	
	# Delete the connection record if it's there so we aren't sending that
	# to remote machines.  It can cause problems due to the size of the 
	# connection record.
	if ( n?$conn )
		delete n$conn;
	if ( n?$iconn )
		delete n$iconn;
	}
	
# Create the ordered notice policy automatically which will be used at runtime 
# for prioritized matching of the notice policy.
event bro_init()
	{
	local tmp: table[count] of set[PolicyItem] = table();
	for ( pi in policy )
		{
		if ( pi$priority < 0 || pi$priority > 10 )
			{
			print "All Notice::PolicyItem priorities must be within 0 and 10";
			exit();
			}
			
		if ( pi$priority !in tmp )
			tmp[pi$priority] = set();
		add tmp[pi$priority][pi];
		}
	
	local rev_count = vector(10,9,8,7,6,5,4,3,2,1,0);
	for ( i in rev_count )
		{
		local j = rev_count[i];
		if ( j in tmp )
			{
			for ( pi in tmp[j] )
				{
				pi$position = |ordered_policy|;
				ordered_policy[|ordered_policy|] = pi;
				Log::write(NOTICE_POLICY, pi);
				}
			}
		}
	}

module GLOBAL;

## This is the entry point in the global namespace for notice framework.
function NOTICE(n: Notice::Info)
	{
	# Fill out fields that might be empty and do the policy processing.
	Notice::apply_policy(n);

	# Run the synchronous functions with the notice.
	for ( func in Notice::sync_functions )
		func(n);

	# Generate the notice event with the notice.
	event Notice::notice(n);
	}
