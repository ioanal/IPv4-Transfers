#!/usr/bin/perl -w
use Net::Patricia;
use File::Basename;

#Prefix classification method that separates routed prefixes (IPv4/IPv6) into four classes: lonely, top, deaggregated and delegated. The method is proposed by Cittadini et al. Lonely and Top prefixes comprise prefixes that are not covered by any other routed prefix. Lonely prefixes do not cover any other routed prefixes, whereas top prefixes cover more specific prefixes. Address space classified as deaggregated and delegated is covered by a less specific prefix in the routing table; deaggreagated space is advertised by the same AS that advertises the less specific prefix, while delegated space is advertised by a different AS. From the ownership perspective, the covering prefix and deaggreagated/delegated prefixes are mapped to the same organization.
 


if(scalar(@ARGV) < 2){
  print STDERR "usage: prefixclassification.pl 6/4 YYYYMM \n";
  exit -1;
}

my $arg_protocol = $ARGV[0];
my $stop = $ARGV[1];

my $fout_top = "top.prefixes_".$stop."_".$arg_protocol;
my $fout_lonely = "lonely.prefixes_".$stop."_".$arg_protocol;
my $fout_delegated = "delegated.prefixes_".$stop."_".$arg_protocol;
my $fout_deaggregated = "deaggregated.prefixes_".$stop."_".$arg_protocol;

my $fout_sum = "classication.prefixes_".$arg_protocol;

#output files for each type of prefixes
print "Top: ".$fout_top."\n";
print "Lonely: ".$fout_lonely."\n";
print "Delegated: ".$fout_delegated."\n";
print "Deaggregated: ".$fout_deaggregated."\n";
print "Classification:\t".$fout_sum."\n";

my $FILEPATH = "/Users/ioana/Documents/Project/RIRv6/data/rtprefix/";
my @files = ();
if($arg_protocol == 4){
  @files = <$FILEPATH"*.prefix2as.bz2">
}else{
  @files = <$FILEPATH"*.prefix2as6.bz2">
}

#open files 
die if(!open(FTOP,">",$fout_top));
die if(!open(FLONELY,">",$fout_lonely));
die if(!open(FDELEG,">",$fout_delegated));
die if(!open(FDEAGG,">",$fout_deaggregated));
die if(!open(FAGG,">",$fout_sum));
foreach my $file (@files)
{
	print $file."\n";
	my $myfile = basename($file);
	my $keytime = substr($myfile,0,6);
	print $myfile."\n";
  
  my $tprefix;
  if($arg_protocol == 4){
    $tprefix = new Net::Patricia; 
  }else{
    $tprefix = new Net::Patricia AF_INET6;
  }
  
  my %prefixall = ();
  my %in_prefix = ();
  my %out_prefix = ();

  my %deaggregated=();
  my %lonely=();
  my %top=();
  my %delegated=();
  die if(!open(FILE,"bzip2 -dc $file|"));
	#die if(!open(FILE," bzip2 -dc $file|"));
	while (<FILE>){
	    chomp($_);
	    if($_ =~ /^#/){next;};
      my @line = split(' ',$_);
	    
      #my $llprefix = $line[0];
      #my @ll_llprefix = split('\/',$llprefix);
      #my $llip = $ll_llprefix[0];
      #my $llblock  = $ll_llprefix[1];
      #my $llasn = $line[1];
      
      my $llip = $line[0];
	    my $llblock = int($line[1]);
	    my $llasn = $line[2];
      my $llprefix = $llip."/".$llblock;
      
      #if($llip eq "::"){next;}
      if($llip eq "0.0.0.0"){next;}
      
      if(($llblock < 8)||($llblock > 24)){next;}
      
      my @aslist=split('\_',$llasn);
      $tprefix->add_string($llprefix);
  
      foreach my $itema (@aslist){
        $prefixall{$llprefix} = $itema;
        $in_prefix{$llprefix} = $itema;
      }
  }
  close FILE;
  
  
  my $no_out  = keys %out_prefix;
  my $no_prefixes = keys %in_prefix;
  print "Total prefixes = ".$no_prefixes."\n";
  
  
  
  my %hmatch = ();
  my $ok = -1;
  do{  
    $ok = 0;
    foreach my $dprefix (sort keys %prefixall){
      #remove prefix
      $tprefix->remove_string($dprefix);
      my $rez = $tprefix->match_string($dprefix);
      if((defined($rez))&&(compareMask($dprefix,$rez) == 0)) {
        $hmatch{$rez}{$dprefix} = 1;
        delete($prefixall{$dprefix});
        $ok = 1;
      }else{
        $tprefix->add_string($dprefix);
      }
    }
    print $ok."\n";
  }while($ok == 1);
  
  my $nn_match = keys %hmatch;
  print "Out of the do-while loop, ok = ".$ok." ".$nn_match."\n";
  
  
  #get deaggregated, delegated, top prefixes prefixes;
  foreach my $dup (sort keys %hmatch){
    my $dasn_up = $in_prefix{$dup};
    foreach my $ddown (sort keys %{$hmatch{$dup}}){
        if((exists($prefixall{$ddown}))||($ddown eq $dup)){ #error
          print "error - $ddown \n";
          exit;
        }
        my $dasn_down = $in_prefix{$ddown};
        if($dasn_down eq $dasn_up){ #deaggregated
          $deaggregated{$ddown} = $dasn_down;
        }else{ #delegated
          $delegated{$ddown} = $dasn_down;
        }
    }
  }
  
  my $nn_deleg = keys %delegated;
  my $nn_deagg = keys %deaggregated;
  print "nn_deleg = ".$nn_deleg."\n";
  print "nn_deagg = ".$nn_deagg."\n";
  
  
  #get lonely prefixes
  foreach my $dprefix (sort keys %prefixall){
    if((exists( $deaggregated{$dprefix}))||(exists($delegated{$dprefix}))){
      print "error -- in deaggregated or delegated";
      exit;
    }
    if(exists($hmatch{$dprefix})){
      $top{$dprefix} = $in_prefix{$dprefix};
    }else{
      $lonely{$dprefix} = $in_prefix{$dprefix};
    }
  }
  
  my $nn_top = keys %top;
  my $nn_lonely = keys %lonely;
  print "nn_top = ".$nn_top."\n";
  print "nn_lonely = ".$nn_lonely."\n";
  
  #save prefixes to files 
	my $str_top = "";
	foreach my $prefix (sort keys %top)	{
    $str_top = $str_top.$prefix."|".$top{$prefix}." ";
	}
	print FTOP $keytime." ".$str_top."\n";
  undef $str_top;
  
	my $str_lonely = "";
	foreach my $prefix (sort keys %lonely)
	{
		$str_lonely = $str_lonely.$prefix."|".$lonely{$prefix}." ";
	}
	print FLONELY $keytime." ".$str_lonely."\n";
  undef $str_lonely;
  
	my $str_delegated = "";
	foreach my $prefix (sort keys %delegated)
	{
		$str_delegated = $str_delegated.$prefix."|".$delegated{$prefix}." ";
	}
	print FDELEG $keytime." ".$str_delegated."\n";
  undef $str_delegated;
  
	my $str_deaggregated = "";
	foreach my $prefix (sort keys %deaggregated)
	{
		$str_deaggregated = $str_deaggregated.$prefix."|".$deaggregated{$prefix}." ";
	}
	print FDEAGG $keytime." ".$str_deaggregated."\n";
  undef $str_deaggregated;
  
  
  my $no_top = keys %top;
  my $no_lonely = keys %lonely;
  my $no_delegated = keys %delegated;
  my $no_deaggregated = keys %deaggregated;
  my $sum_prefixes = $no_top + $no_lonely + $no_delegated+$no_deaggregated;
  my $fr_top = $no_top/$sum_prefixes;
  my $fr_lonely = $no_lonely/$sum_prefixes;
  my $fr_delegated = $no_delegated/$sum_prefixes;
  my $fr_deaggregated = $no_deaggregated /$sum_prefixes;
  
  foreach my $dp (sort keys %top){
    if(exists($lonely{$dp})){
      print $dp." -- top , lonely\n";
      
    }
    if(exists($delegated{$dp})){
      print $dp." -- top , delegated\n";
    }
    if(exists($deaggregated{$dp})){
      print $dp." -- top , deaggregated\n";
    }
  }
  foreach my $dp (sort keys %lonely){
    if(exists($delegated{$dp})){
      print $dp." -- top , delegated\n";
    }
    if(exists($deaggregated{$dp})){
      print $dp." -- top , deaggregated\n";
    }
  }
  foreach my $dp (sort keys %delegated){
    if(exists($deaggregated{$dp})){
      print $dp." -- top , deaggregated\n";
    }
  }
  
  if($no_prefixes != $sum_prefixes){
    print "error -- check number of prefixes: ".$no_prefixes." ".$sum_prefixes."\n";
    print "error -- check number of prefixes\n";
    exit;
  }
  print $keytime."--".$sum_prefixes." -- ".$no_top." ".$no_delegated." ".$no_deaggregated." ".$no_lonely." -- ".$fr_top." ".$fr_delegated." ".$fr_deaggregated." ".$fr_lonely."\n";
  print FAGG $keytime." ".$sum_prefixes." ".$no_top." ".$no_delegated." ".$no_deaggregated." ".$no_lonely."\n";
  
  
  undef %hmatch;
  undef %prefixall;
  undef %deaggregated;
  undef %lonely;
  undef %top;
  undef %delegated;
}
close FTOP;
close FLONELY;
close FDELEG;
close FDEAGG;
close FAGG;

sub compareMask{
	my $low=$_[0];
	my $up=$_[1];
	my @listlow=split('\/',$low);	#$listlow[1]
	my @listup=split('\/',$up);	#$listup[1]
	
	my $result=1;
	if($listup[1] < $listlow[1]){
		$result=0;
	}
	return $result;
}
