#!/bin/bash
# -x

# newgit.sh [ -i ] [ -n <projectname> ] [ -g ] [ -t <githubtoken> ] [ -u <username> ] [ -p <password> ] [ -s <remote-git-system> ] [ -d <remote-git-dir> ] [ -T <project-type> ]

# this assumes you've created a project locally (or it will create a brand new one itself if given "-i"), and are managing it via git, again, just with a local repo.
# now you want to use some remote thing as the "origin"

# run this script in the top directory of the project (where ".git/" lives)
# it will set up a bare git repo of the same folder name (with ".git" appended) at whatever "$remotebase" is

# the hostname on which to put the repo
# honors "REMOTE_GIT_SYSTEM" environment variable
#remoteSystem='example.com'
# the account to which you have SSH access
# honors "REMOTE_GIT_USER" environment variable
#remoteAccount='example'

# EXAMPLES:
#
#   newgit.sh -n mynewproject -g -T Node
# Create a brand new project here called "mynewproject", and keep it at GitHub.  Initialize .gitignore for NodeJS
#
#   newgit.sh -i
# I'm in a directory with existing code that I want to put under GIT version control
# It will host the git repo on my private server (using REMOTE_GIT_SYSTEM and REMOTE_GIT_USER environment variables)
# The project is auto-named the name of the current directory.
# If it looks like a known project type, a .gitignore file will be created for it before committing anything.

# TODO: support multiple project types for .gitignore initialization, both command-line and guessed
# TODO: support naming the project as something other than the directory name (-n option coupled with -i)
# TODO: massive code cleanup, sheesh
# TODO: better documentation and example use-cases
# TODO: use "git init <directory>" for plain "-n newprojectname" instead of manually creating it...  I didn't realize that was available

# The directory in which all the repos live, if on a private server.
remoteDir='git' # in this case, just "git/" in the login account's home dir

####
#### Don't change anything past here
####

# a repo we can pull stuff from that is useful for initializing .gitignore files
gitignoreBase="https://raw.github.com/github/gitignore/master"
# $1 is the project type, $2 is a message.
function pullGitignore() {
  projectGitignoreURL="$gitignoreBase/$1.gitignore"
  tmpGitignore="tmpGitignore$$"
  curl --location --write-out "%{http_code}" --url "$projectGitignoreURL" --output $tmpGitignore.tmp --fail > $tmpGitignore.out 2> $tmpGitignore.err
  result=$?
  if [ $result -ne 0 ]; then
    echo "Was unable to retrieve .gitignore information from: $projectGitignoreURL"
    echo "Perhaps '$1' is not a valid/known type in the list?"
    echo -n "Response code was: "
    cat $tmpGitignore.out
    echo
    echo -n "And curl said: "
    cat $tmpGitignore.err
    echo
  else
    echo "$2  Appending to .gitignore from:"
    echo "    $projectGitignoreURL"
    # Append, in case there was already a ".gitignore" file here.
    # Yes, we might end up duplicating rules.  So what?
    echo >> .gitignore
    echo "#" >> .gitignore
    echo "# START FROM: $projectGitignoreURL" >> .gitignore
    echo "# RETRIEVED: `date --iso-8601=ns --reference=$tmpGitignore.tmp`" >> .gitignore
    echo "#" >> .gitignore
    cat $tmpGitignore.tmp >> .gitignore
    echo >> .gitignore
    echo "#" >> .gitignore
    echo "# END FROM: $projectGitignoreURL" >> .gitignore
    echo "# RETRIEVED: `date --iso-8601=ns --reference=$tmpGitignore.tmp`" >> .gitignore
    echo "#" >> .gitignore
  fi

  # cleanup all the temp files we createde while CURLing
  /bin/rm -f $tmpGitignore.tmp $tmpGitignore.out $tmpGitignore.err
}

while getopts "?hxiGHn:s:d:u:p:T:t:" flag
do
#  echo "$flag" $OPTIND $OPTARG
  case "$flag" in
    i)  initialize="true";;
    G)  useGithub="true";;
    H)  useHeroku="true";;
    n)  newProjectName="$OPTARG";;
    s)  remoteSystem="$OPTARG";;
    d)  remoteDir="$OPTARG";;
    u)  remoteAccount="$OPTARG";;
    p)  password="$OPTARG";;
    T)  projectType="$OPTARG";;
    t)  githubToken="$OPTARG";;
    x)  set -x;;
    [?h]) echo >&2 "Usage: $0 [ -?hx ] [ -i ] [ -n <projectname> ] [ -H ] [ -G ] [ -t <githubtoken> ] [ -u <username> ] [ -p <password> ] [ -s <remote-git-system> ] [ -d <remote-git-dir> ] [ -T <project-type> ]"
      exit 1;;
  esac
done
shift $((OPTIND-1))

if [ "$remoteSystem" == "" -a "$useGithub" != "true" ]; then
  if [ "$REMOTE_GIT_SYSTEM" != "" ]; then
    remoteSystem="$REMOTE_GIT_SYSTEM"
  else
    echo "Need either a remote system ( -s ) or to be told to use GitHub ( -G ).  Quitting."
    exit 99
  fi
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
  if [ "$REMOTE_GIT_USER" != "" ]; then
    remoteAccount="$REMOTE_GIT_USER"
  else
    echo "Can't do anything without a user name ( -u ).  Quitting."
    exit 99
  fi
fi

if [ "$useGithub" == "true" -a "$githubToken" == "" ]; then
  fromConfig=`git config --get github.token` # really, not sure it's healthy if we find this
  if [ "$GITHUB_TOKEN" != "" ]; then
    githubToken="$GITHUB_TOKEN"
  elif [ "$fromConfig" != "" ]; then
    githubToken="$fromConfig"
  fi
fi

if [ "$useGithub" == "true" -a "$password" == "" ]; then
  fromConfig=`git config --get github.password` # really, not sure it's healthy if we find this
  if [ "$GITHUB_PASSWORD" != "" ]; then
    password="$GITHUB_PASSWORD"
  elif [ "$fromConfig" != "" ]; then
    password="$fromConfig"
  fi
fi

if [ "$useGithub" == "true" ]; then # using v3 of the API
  gitHubAuthFlag="-u" # default to assuming username/password
  if [ "$githubToken" != "" ]; then
    gitHubAuthFlag="-H" # this is the only case where it's not "-u", so override
    gitHubAuthString="Authorization: token $githubToken"
  elif [ "$password" != "" ]; then
    gitHubAuthString="$remoteAccount:$password"
  else
    # this will just prompt interactively for the password
    gitHubAuthString="$remoteAccount"
  fi
fi

# the "-n <projectname>" option will create a new git repo here, with just a simple README, and then push it out to the remote site
if [ "$newProjectName" != "" ]; then
  if [ -d "$newProjectName" ]; then
    echo "There was already a directory with the name '$newProjectName'."
  else
    echo "Making brand new '$newProjectName' project."
    mkdir "$newProjectName"
    if [ $? -ne 0 ]; then
      echo "Failed to create a directory with the name '$newProjectName' (and not because it already existed, at least not as a directory).  This may go badly."
    fi
  fi

  cd "$newProjectName"
  if [ $? -ne 0 ]; then
    # if we can't go there, then we're almost certainly going to do something bad, like create a ridiculously
    #   large git repo one directory up from where it was supposed to go.  let's not do that.
    echo "Failed to cd into '$newProjectName'.  I'm going to give up here, before I do more damage."
    exit 66
  fi

  if [ "$projectType" != "" ]; then
    pullGitignore "$projectType" "You are starting a(n) $projectType project."
  fi

  echo "This is $newProjectName" > README

  git init
  git add .
  git commit -m "Initial commit."
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
  #   to at least try to have an appropriate .gitignore file
  if [ -f "AndroidManifest.xml" ]; then
    projectType="Android";
  elif [ -f "Gemfile" ]; then # "config.ru" or "Rakefile" are probably just as reasonable
    projectType="Rails";
  fi
  if [ "$projectType" != "" ]; then
    pullGitignore "$projectType" "Looks like a(n) $projectType project."
  else
    echo "Not sure what kind of project this is, so not pulling any .gitignore file"
  fi

  if [ `ls | wc -l` = 0 ]; then
    # handle case where they've asked to initialize a totally empty directory...
    # this is a dumb thing to do, but it's more confusing if we just ignore it.
    echo "You asked me to initialize an entirely empty directory.  Creating a README file to unconfuse GIT."
    echo "This is $projectName" > README
  fi

  git init
  git add .
  git commit -m "Initial commit."
fi

# GitHub API v3
if [ "$useGithub" == "true" ]; then
  # we need to hold on to what GitHub tells us, in case there's some kind of error.
  # we're logging the info up one directory, so it's out of the source location
  gitHubResultFile="../tmp$$.json"

  # we've set up either "-u" and "username:password", or "-H" and the token header, for the auth flag and auth string, earlier on
  curl -o "$gitHubResultFile" -d '{"name":"'"$projectName"'"}' "$gitHubAuthFlag" "$gitHubAuthString" "https://api.github.com/user/repos"

  resultMessages=`fgrep '"message": ' "$gitHubResultFile"` # let's take a look if everything went smoothly
  if [ -n "$resultMessages" ]; then # if it's nonzero, then we had some kind of message in the results.  we assume this is bad news.
    # "Bad Credentials" means that's a bogus token, or the username/password does not compute
    badCredentials=`echo "$resultMessages" | fgrep "Bad Credentials"`
    notFound=`echo "$resultMessages" | fgrep "Not found"`
    validationFailed=`echo "$resultMessages" | fgrep "Validation Failed"`

    if [ -n "$badCredentials" ]; then
      if [ "$githubToken" = "" ]; then # we didn't have a token, so it must be username/password
        if [ "$password" != "" ]; then # the password is already stored somewhere, so I don't feel too bad emitting it.
          # Though if the output gets logged somewhere, this might not be such a good idea
          echo "This username/password combination is invalid, according to GitHub: $gitHubAuthString"
        else # they just gave the username, and typed the password by hand
          echo "Either this isn't the correct username ('$gitHubAuthString') or you mistyped the password, according to GitHub."
        fi
      else # we had a token
        echo "This isn't a valid token, according to GitHub: $githubToken"
      fi

    elif [ -n "$notFound" ]; then
      # "Not found" means the token (perhaps also username/password combo?) are valid, but doesn't allow access to this action
      #   (in this case, probably the token doesn't have the required scope)
      echo "While your authentication succeeded, you are probably not authorized to create a new repo."

    elif [ -n "$validationFailed" ]; then
      # "Validation Failed" has additional info
      nameAlreadyExists=`echo "$resultMessages" | fgrep "name already exists on this account"`
      if [ -n "$nameAlreadyExists" ]; then
        # I've seen it say this when trying to create a repo with a name that already exists
        echo "It looks like you probably already have a GitHub repo by that name ('$projectName')."
      else # TODO: find out if there are other modes of failure that will take us here (i.e. "Validation Failed")
        echo "Validation failed for some reason I'm not familiar with."
      fi

    else
      # TODO: find out if there are other situations that will give us "message:" in the result,
      # and whether they can be okay, or definitely bad news
      echo "Something went wrong that I'm not prepared to interpret."
    fi

    echo "I'm going to stop here and give you the result GitHub returned.  Best of luck!"

    gitHubResultHumanReadableFileName="$gitHubResultFile"
    if [ "$newProjectName" != "" ]; then
      # fix this up (strip the leading "../") since from the user's perspective, it's actually where the command was run from
      gitHubResultFileName=`echo "$gitHubResultFile" | cut -c4-`
    fi
    echo "The result is also stored in '$gitHubResultFileName', but here it is right now:"
    echo
    cat "$gitHubResultFile"

    exit 77
  fi

  /bin/rm -f "$gitHubResultFile" # clean up, nothing bad happened

  remoteBase="git@github.com:$remoteAccount"

else # else we're not using GitHub, so we set this up on a private server somewhere

# this is fragile!
# 1) if "$remoteDir" doesn't already exist, it'll try to create it.
#      If it fails, bad things will probably happen.  It'll put it directly in the user's home dir?
# 2) if "$projectName.git" already exists, we shouldn't do this either
  ssh "$remoteAccount@$remoteSystem" "
if [ ! -d '$remoteDir' ]; then
  echo '$remoteDir not found.  Creating...'
  mkdir -p '$remoteDir'
  if [ $? -ne 0 ]; then
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
# TODO: learn what "-u" option really means and whether it should be used here

# okay, let's also dump it out on Heroku if that was requested
if [ "$useHeroku" == "true" ]; then
  # in case we don't already have heroku
#  echo "Installing heroku gem, in case it's not already here:"
#  gem install heroku
#  echo "DONE Installing heroku gem."

  echo "Creating a Heroku app named '$projectName':"
  tmpHeroku="tmpHeroku$$"
  heroku apps:create $projectName > $tmpHeroku.out 2> $tmpHeroku.err
  result=$?
  if [ $result -ne 0 ]; then
    echo "Failed to create Heroku app with name $projectName (returned: $result)"
  else
    echo "Successfully created Heroku app with name $projectName"
  fi
  echo "Here's what Heroku had to say:"
  cat $tmpHeroku.out $tmpHeroku.err

  echo "----- That's all Heroku had to say"

  # TODO: stop trying to create directly with the desired name
  # TODO: instead, create with temporary name, then try to rename.  More gets done that way even if there's a name conflict.

  # create ( heroku apps:create <NAME1> ) returns the following
  # ON SUCCESS- 0
  # OUT: Creating <NAME1>... done, stack is cedar
  #      http://<NAME1>.herokuapp.com/ | git@heroku.com:<NAME1>.git
  # ERR: <empty>
  # ON FAILURE- 1 (when there is already an app with the name NAME1)
  # OUT: <empty>
  # ERR: !    Name is already taken

  # create ( heroku apps:create ) (i.e. without a designated name) returns the following
  # ON SUCCESS- 0
  # OUT: Creating <NAME>... done, stack is cedar
  #      http://<NAME>.herokuapp.com/ | git@heroku.com:<NAME>.git
  # ERR: <empty>
  # ON FAILURE...  Haven't yet found a failure mode
  # OUT:
  # ERR:

  # rename ( heroku apps:rename <NAME2> --app <NAME1> ) returns the following
  # ON SUCCESS- 0
  # OUT: Renaming <NAME1> to <NAME2>... done
  #      http://<NAME2>.herokuapp.com/ | git@heroku.com:<NAME2>.git
  #      Don't forget to update your Git remotes on any local checkouts.
  # ERR: <empty>
  # ON FAILURE- 1 (when there is already an app with the name NAME2)
  # OUT: Renaming <NAME1> to <NAME2>... failed
  # ERR: !    is already taken
  # ON FAILURE- 1 (when there is no app with the name NAME1)
  # OUT: Renaming <NAME1> to <NAME2>... failed
  # ERR: !    App not found.

  /bin/rm -f $tmpHeroku.out $tmpHeroku.err

  echo
  echo "Pushing to Heroku..."
  git push heroku master
  echo "DONE Pushing to Heroku."

  echo
  echo "Running 'rake db:setup' on Heroku..."
  heroku run rake db:setup
  echo "DONE Running 'rake db:setup' on Heroku."

  echo
  echo "Running 'heroku ps'..."
  heroku ps
  echo "DONE Running 'heroku ps'..."

  echo
  echo "Running 'heroku logs'..."
  heroku logs
  echo "DONE Running 'heroku logs'..."

fi
