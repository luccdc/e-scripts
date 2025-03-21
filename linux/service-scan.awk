#!/usr/bin/env -S awk -f
BEGIN {
	IS_RHEL = system("test -f /etc/redhat-release") == 0
	VALID_STARTEXEC = 1
	FROM_PACKAGE = 1
	FS = "="
	ls
}

/ExecStart=/ {
	match($3, /\/[^;]*/)
	program = substr($3, RSTART, RLENGTH - 1)
	if (belongs_to_package_p(program)) {
		valid = validate(program)
		if (valid != "") {
			VALID_STARTEXEC = 0
			print "potentially altered program!"
			print program
			print valid
		}
	} else {
		FROM_PACKAGE = 0
		print "Program does not come from a package!"
		print program
	}
}

/FragmentPath=/ {
	service_path = $2
	FROM_PACKAGE = belongs_to_package_p(service_path)
	VALID_STARTEXEC = valid_p(service_path)
}

/Id=/ {
	service_name = $2
	if (! FROM_PACKAGE) {
		print "Service does not come from a package!"
	}
	if (! VALID_STARTEXEC && ! FROM_PACKAGE) {
		print "From service: " service_name "\n"
		VALID_STARTEXEC = 1
	}
}


function belongs_to_package_p(file)
{
    # Return true if file belongs to a package,
    # false otherwise.
	if (find_package(file) != "") {
		return 0
	} else {
		return 1
	}
}

function find_package(file)
{
	# find_package finds the package that owns a specific file.
	# If there is no package, it returns an empty string.
	package = ""
	if (IS_RHEL) {
		cmd = "rpm -qf " file
	} else {
		# Ensure pipe into cut doesn't happen if the package doesn't exist
		cmd = "( set -o pipefail ;             dpkg -S " file " | cut -d: -f1)"
	}
	if ((cmd | getline package) != 0) {
		package = ""
	}
	close(cmd)
	return package
}

function valid_p(file)
{
    # return true if a file passes validation,
    # false otherwise.
	if (validate(file) != "") {
		return 0
	} else {
		return 1
	}
}

function validate(file)
{
	# validate determines whether a file is unchanged from its installation.
	# Behavior on Debian and Red Hat systems differs slightly.
	# On Debian, it validates an entire package at once, and will print
	# every file that has been changed. This includes configuration files.
	# On Red Hat, it only reports the specific file that has been modified.
	valid = ""
	if (IS_RHEL) {
		cmd = "rpm -Vf " file
	} else {
		package = find_package(file)
		cmd = "dpkg -V " package
	}
	cmd | getline valid
	close(cmd)
	return valid
}
