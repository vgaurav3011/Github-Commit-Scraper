NOCOLOR='\033[0m'
red() { CRED='\033[0;31m'; echo -e ${CRED}$@${NOCOLOR}; }
blue() { CBLUE='\033[0;34m'; echo -e ${CBLUE}$@${NOCOLOR}; }
green() { CGREEN='\033[0;32m'; echo -e ${CGREEN}$@${NOCOLOR}; }

up() {
    if [ "$1" = "0" ] || [ "$1" = "" ]; then 
	return 0
    fi
    printf "\033[$1A"
    for i in `seq $1`; do
	echo -e "\033[K"
    done
    printf "\033[$1A"
}

search_term="removed+private+key"

get_commits() {
    echo "[*] Searching $pages pages..."
    if [ -f $RES ]; then 
	[ ! -d stash ] && mkdir stash
	num=$(ls stash | cut -d'-' -f1 | sort -n | tail -n 1)
	fff="stash/$(($num +1))-$RES"
	mv $RES "stash/$(($num +1))-$RES"
	[ $? = 0 ] && up 1 && green "[+] Backed up $RES to $fff" && echo
    fi
    echo > $RES
    [ $? != 0 ] && red "[!] Error creating $RES" && exit
    count=0
    for p in $(seq $pages); do
	up $count
	link="https://github.com/search?p=$p&q=$search_term&type=Commits"
	up 1
	blue "[$p/$pages] Getting Repositories $link"
	search=$(curl -s "$link")
	links=$(echo "$search" | grep "Browse the repository at this point in the history")
	echo "$links" | sed 's/.*href="\(.*\)" aria.*/\1/p' | uniq >> $RES
	repos=$(echo "$links" | sed 's/.*href="\(.*\)" aria.*/\1/p' | uniq)
	up 1
	count=$(echo "$repos" | wc -l)
	green "[$p/$pages] Found $count repositories on page $p"
	echo "$repos"
	sleep 5
    done
    grep -v ^$ $RES | uniq > ${RES}.2
    [ $? = 0 ] && mv ${RES}.2 $RES
    up $(($count+1))
    echo "[+] Found" $(wc -l $RES | cut -d' ' -f1) "project(s)"
}

get_files() {
    if [ ! -f "$RES" ]; then
	red "[!] $RES Does not exist!"
	exit
    fi
    MAX=$(cat $RES | wc -l)
    CUR=1
    # If the found dir doesnt exist, create it, else delete everything in it
    [ -d $dirr/found ] && rm $dirr/found/* -fr || mkdir -p $dirr/found
    while read link; do
	if [ "$link" == "" ]; then
	    red "[!] Blank Line"
	    continue
	fi
	B="[$CUR/$MAX]"
	CUR=$(($CUR + 1))
	name=$(echo $link | sed -ne 's:/\(.*\)/tree/.*:\1:p')
	commit=$(echo $link | sed -n 's:.*tree/\(.*\):\1:p')
	cd $dirr
	rm -fr tmp/curr	
	cd tmp
	blue "$B [$name] Cloning repository..."
	git clone https://github.com/$name curr &>/dev/null
	# If this fail then skip all the next stuff
	if [ $? = 0 ]; then
	cd curr

	# Make sure the commit is still there
	git cat-file $commit~1 -t &>/dev/null
	retval=$?
	if [ $retval != 0 ]; then
	    up 1
	    red "$B [$name] Error commit doesnt exist $commit~1"
	    cd ../../
	    rm -fr tmp/curr
	    continue
	else
	    up 1
	    green "$B [$name] Commit exists $commit~1"
	fi
	
	# Get the files that have changed
	files=$(git diff "$commit~1" $commit --name-only )
	num_fils=$(echo "$files" | wc -l)
	
        # Checkout the commit before the change
	git checkout $commit~1 &>/dev/null
	if [ $? != 0 ]; then
	    up 1
	    red "$B [$name] Error cannot checkout $commit~1"
	    continue
	else
	    up 1
	    green "$B [$name] Checked out $commit~1"
	fi
	
	good_files=0
	for f in $files; do
	    # Make sure the file is ASCII
	    isascii="$(file $f | grep -e '(ASCII|TEXT'))"
	    if [ "$isascii" != "" ]; then 
		# Get the commit difference
		git show "$commit~1":$f &>/dev/null
		[ $? != 0 ] && up 1 && red "$B [$name] File doesn't exist in \
		$commit~1"  && continue

		change=$(git show "$commit~1":$f)
		# Check if this contains a key
		if [ "$(echo $change | grep 'PRIVATE KEY')" != "" ]; then
		    good_files=$(($good_files +1))
		    # Make the output fold and make the filename
		    fil=$(echo $f | sed 's=.*/==' )
		    output_folder="$dirr/found/$(echo $name| cut -d'/' -f2)---$fil"
		    # Save the file that has potential
		    git show "$commit~1":$f > "$output_folder" 
		fi
	    else
		:
		#echo "[!] Non-text $f $(file $f)"
	    fi
	done

	# Print the status
	up 1
	if [ $good_files != 0 ]; then
	    green "$B [$name] $good_files/$num_fils files have potential"
	else
	    echo "$B [$name] $good_files/$num_fils files have potential"
	fi

	else
	    up 1
	    red "[!] Error cloning $name"
	fi
	#echo [+] Done with $name
    done < $RES
    cd $dirr
    rm -fr tmp/curr	
    echo "[*] Found $(ls $dirr/found | wc -w) files"
}

parse_files() {
    [ ! -d $dirr/found ] && return 1
    DIR="keys"
    [ ! -d $dirr/$DIR ] && mkdir $dirr/$DIR
    if [ "`ls $dirr/$DIR`" != "" ]; then
	num=$(find $dirr/stash/* -type d | sed 's:.*/\([^/]*\)$:\1:p' \
	| cut -d'-' -f1 | sort -n | tail -n 1)
	num=$(($num+1))
	mkdir -p "$dirr/stash/$num-keys"
	mv $dirr/$DIR/*  "$dirr/stash/$num-keys"
    fi
    green '[+] Parsing files'
    cd $dirr/found
    files=$(find ./ -type f)
    count=0
    for f in $files; do
	up 1
	green "[$f] Parsed"
	if [ "$(grep 'BEGIN.*END' $f )" = "" ]; then
	    cat $f | sed '/BEGIN/,/END/!d'  > ../$DIR/$f
	else
	    printf "$(cat $f)" | sed -e '/BEGIN/,/END/!d' > ../$DIR/$f
	fi
	begin_string='/BEGIN/ s:^.*\(-----BEGIN.*\)$:\1:'
	end_string='s:^\(.*KEY-----\).*$:\1:'
	sed -i "$begin_string; $end_string" ../$DIR/$f
	echo >> ../$DIR/$f
	cat ../$DIR/$f | grep -v ^$ > ../$DIR/${f}.2
	[ $? = 0 ] && [ -f ../$DIR/${f}.2 ] && mv ../$DIR/${f}.2 ../$DIR/$f
	count=$(($count +1))	
    done
    up 1
    echo "[+] $count Files Parsed"
}

parse() {
    case "$1" in
	parse|p )
	parse_files
	;;
	extract|e )
	get_files
	;;
	find|f )
	read -p "how many pages to pull? " pages
	get_commits
	;;
	all|a)
	read -p "how many pages to pull? " pages
	get_commits
	get_files
	cd $dirr
	parse_files
	;;
	*)
	echo -e "USAGE: $0 <command>\n\nCOMMANDS:
find
    Search github for a list of commits and projects for potential private keys
extract
    clones the repositories and extracts private keys from the files flagged
parse
    parses the extracted files and outputs a list of clean keys in \"./keys/\"
all
    Runs all three commands
"
	exit
	;;
    esac
}

init() {
    git config --global core.autocrlf false
    RES=search_results.txt
    dirr=$PWD
    # Create the temp directory if it doesnt exist
    [ ! -d "tmp" ] && mkdir tmp
}

init
parse $1
