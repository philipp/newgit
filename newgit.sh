#!/bin/sh
# -x

# newgit.sh [ -i ] [ -n <projectname> ] [ -g ] [ -t <githubtoken> ] [ -u <username> ] [ -p <password> ] [ -s <remote-git-system> ] [ -d <remote-git-dir> ] [ -T <project-type> ]

# this assumes you've created a project locally (or it will create a brand new one itself if given "-i"), and are managing it via git, again, just with a local repo.
# now you want to use some remote thing as the "origin"

# run this script in the top directory of the project (where ".git/" lives)
# it will set up a bare git repo of the same folder name (with ".git" appended) at whatever "$remotebase" is

# the hostname on which to put the repo
#remoteSystem='example.com'
# the account to which you have SSH access
#remoteAccount='example'

# the directory in which all the repos live
remoteDir='git' # in this case, just "git/" in the login account's home dir

####
#### Don't change anything past here
####

gitignoreBase="https://raw.github.com/github/gitignore/master/"

while getopts "ign:s:d:u:p:T:t:" flag
do
#		echo "$flag" $OPTIND $OPTARG
		case "$flag" in
				i)	initialize="true";;
				g)	useGithub="true";;
				n)	newProjectName="$OPTARG";;
				s)	remoteSystem="$OPTARG";;
				d)	remoteDir="$OPTARG";;
				u)	remoteAccount="$OPTARG";;
				p)	password="$OPTARG";;
				T)	projectType="$OPTARG";;
				t)	githubToken="$OPTARG";;
				[?])	print >&2 "Usage: $0 [ -i ] [ -n <projectname> ] [ -g ] [ -t <githubtoken> ] [ -u <username> ] [ -p <password> ] [ -s <remote-git-system> ] [ -d <remote-git-dir> ] [ -T <project-type> ]"
						exit 1;;
		esac
done
shift $((OPTIND-1))

if [ "$remoteSystem" == "" -a "$useGithub" != "true" ]; then
		echo "Need either a remote system ( -s ) or to be told to use GitHub ( -g ).  Quitting."
		exit 99
fi

if [ "$remoteAccount" == "" -a "$useGithub" == "true" ]; then
		fromConfig=`git config --get github.user`
		if [ "$GITHUB_USER" != "" ]; then
				remoteAccount="$GITHUB_USER"
		elif [ "$GITHUB_USERNAME" != "" ]; then
				remoteAccount="$GITHUB_USERNAME"
		elif [ "$GITHUB_LOGIN" != "" ]; then
				remoteAccount="$GITHUB_LOGIN"
		elif [ "$fromConfig" != "" ]; then
				remoteAccount="$fromConfig"
		fi
fi
# okay, I've tried everything that makes sense to me right now		
if [ "$remoteAccount" == "" ]; then
		echo "Can't do anything without a user name ( -u ).  Quitting."
		exit 99
fi

if [ "$useGithub" == "true" -a "$githubToken" == "" ]; then
		fromConfig=`git config --get github.token`
		if [ "$GITHUB_TOKEN" != "" ]; then
				githubToken="$GITHUB_TOKEN"
		elif [ "$fromConfig" != "" ]; then
				githubToken="$fromConfig"
		fi
fi

if [ "$useGithub" == "true" -a "$password" == "" ]; then
		fromConfig=`git config --get github.password`
		if [ "$GITHUB_PASSWORD" != "" ]; then
				password="$GITHUB_PASSWORD"
		elif [ "$fromConfig" != "" ]; then
				password="$fromConfig"
		fi
fi

if [ "$useGithub" == "true" ]; then # using v3 of the API
		if [ "$githubToken" != "" ]; then
				githubTokenHeader="Authorization: token $githubToken"
		elif [ "$password" != "" ]; then
				githubAuth="$remoteAccount:$password"
		else
				# this will just prompt interactively for the password
				githubAuth="$remoteAccount"
		fi
fi

# the "-n <projectname>" option will create a new git repo here, with just a simple README, and then push it out to the remote site
if [ "$newProjectName" != "" ]; then
		echo "Making brand new '$newProjectName' project."
		mkdir "$newProjectName"
		cd "$newProjectName"

		git init
		echo "First Post" > README
		git add .
		git commit -m "Initial commit.  README only."
fi

cwd=`pwd`
projectName=`basename "$cwd"` # we checked for ".git/" above, so assume we're in the right place

# I think this is the most generic way of testing for spaces (i.e. doesn't require 'bash' but
#   should even work in plan vanilla/vintage 'sh'
# TODO: look for other possibly-problematic characters?
# Truth is, coded defensively enough, even spaces aren't a big deal, but I do consider them to
#   be a form of just asking for trouble in the future, depending on the rest of your toolchain
case "$projectName" in 
    *[[:space:]]*) 
				echo "Please don't give me spaces in the project name! (I see: '$projectName')  Quitting."
				exit 99
        ;; 
esac

if [ ! -d ".git" ]; then # no .git here?  This gets a little dicey, but let's allow it
		if [ "$initialize" != "true" ]; then # okay, no, not if they didn't say to initialize it
				echo "I don't see a '.git/' directory here and you didn't pass me the '-i' option.  Quitting."
				exit 99
		fi

		# Not all that sure how to identify different kinds of projects.  But it seems worthwhile
		#   to at least have an appropriate .gitignore file
		projectType="UNKNOWN";
		if [ -f "AndroidManifest.xml" ]; then
				projectType="Android";
		elif [ -f "Gemfile" ]; then # config.ru or Rakefile are probably just as reasonable
				projectType="Rails";
		fi
		if [ "$projectType" != "UNKNOWN" ]; then
				# Append, in case there was already a ".gitignore" file here.
				# Yes, we might end up duplicating rules.  So what?
				curl "$gitignorebase/$projectType.gitignore" >> .gitignore
		fi
		
		git init
		git add .
		git commit -m "Initial commit."
fi

if [ "$useGithub" == "true" ]; then
		# this doesn't seem to work for me...  going to try with API v3
#		curl -F "login=$remoteAccount" $githubAuth "https://github.com/api/v2/json/repos/create" -F "name=$projectName" # -F 'description=This project is a test'
		# I think '-u "$remoteAccount/$password"' or '-u "$remoteAccount/token:$githubToken"' might also work in place of '-F "login=$remoteAccount" -F "$githubAuth"'

		if [ "$githubTokenHeader" != "" ]; then
				curl -d '{"name":"'"$projectName"'"}' -H "$githubTokenHeader" "https://api.github.com/user/repos"
		else
				curl -d '{"name":"'"$projectName"'"}' -u "$githubAuth" "https://api.github.com/user/repos"
		fi

		remoteBase="git@github.com:$remoteAccount"
else

# this is fragile!
# 1) if "$remoteDir" doesn't already exist, it'll try to create it.  If it fails, bad things will probably happen.  It'll put it directly in the user's home dir?
# 2) if "$projectName.git" already exists, we shouldn't do this either
ssh "$remoteAccount@$remoteSystem" "
if [ ! -d '$remoteDir' ]; then
  echo '$remoteDir not found.  Creating...'
  mkdir -p '$remoteDir'
  if [ $? ]; then
    echo 'Unable to mkdir -p $remoteDir.  This may not end well.'
    exit
  fi
fi

cd '$remoteDir'
if [ -d '$projectName.git' ]; then
  echo '$projectName.git already existed in $remoteDir.  I hope this was what you were expecting...'
else
  mkdir '$projectName.git'
  if [ ! -d '$projectName.git' ]; then
    echo 'Apparently unable to mkdir $projectName.git in $remoteDir.  This will DEFINITELY not end well.'
    exit
  fi
fi
cd '$projectName.git'
git --bare init
"

remoteBase="$remoteAccount@$remoteSystem:$remoteDir"

fi


git remote add origin "$remoteBase/$projectName.git"
git config master.remote origin
git config master.merge refs/heads/master

# and shovel it all out there
git push -u origin master
