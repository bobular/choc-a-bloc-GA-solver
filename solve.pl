#!/usr/bin/env perl
#          -*- mode: cperl -*-
#
use strict;
use warnings;
use PDL;
use PDL::IO::Pic;
use Getopt::Long;

my $population_size = 5000;
my $mating_from_best = 50;
my $mate_times = 2; # best integer > 1
my $mutation_rate = 0.02; # probability (ish) per gene
my $board_size = 42;
my $max_piece_size = 5; # all pieces fit in 4x4 square
my $prefix = 'best';
my $output_frequency = 10; # save a PNG every N generations


GetOptions("prefix=s"=>\$prefix);


my @pieces =
  (
   pdl(
       [0,0,0,0,0],
       [0,0,0,1,0],
       [0,0,0,1,0],
       [0,1,1,1,0],
       [0,0,0,0,0],
      ),

   pdl(
       [0,0,0,0,0],
       [0,0,0,0,0],
       [0,1,0,1,0],
       [0,1,1,1,0],
       [0,0,0,0,0],
      ),
   pdl(
       [0,0,0,0,0],
       [0,0,0,1,0],
       [0,0,1,1,0],
       [0,1,1,0,0],
       [0,0,0,0,0],
      ),
   pdl(
       [0,0,1,0,0],
       [0,0,1,0,0],
       [0,0,1,0,0],
       [0,0,1,0,0],
       [0,0,1,0,0],
      ),
   pdl(
       [0,1,1,0,0],
       [0,0,1,0,0],
       [0,0,1,0,0],
       [0,0,1,0,0],
       [0,0,0,0,0],
      ),
   pdl(
       [0,0,0,0,0],
       [0,0,0,1,0],
       [0,0,0,1,0],
       [0,0,1,1,0],
       [0,0,0,1,0],
      ),
   pdl(
       [0,0,0,0,0],
       [0,0,1,0,0],
       [0,1,1,0,0],
       [0,1,1,0,0],
       [0,0,0,0,0],
      ),
   pdl(
       [0,0,0,0,0],
       [0,0,1,0,0],
       [0,0,1,1,0],
       [0,1,1,0,0],
       [0,0,0,0,0],
      ),
   pdl(
       [0,0,0,0,0],
       [0,0,1,0,0],
       [0,1,1,1,0],
       [0,0,1,0,0],
       [0,0,0,0,0],
      ),
   pdl(
       [0,0,0,0,0],
       [0,1,1,1,0],
       [0,0,1,0,0],
       [0,0,1,0,0],
       [0,0,0,0,0],
      ),
   pdl(
       [0,0,1,0,0],
       [0,0,1,0,0],
       [0,1,1,0,0],
       [0,1,0,0,0],
       [0,0,0,0,0],
      ),
   pdl(
       [0,0,0,0,0],
       [0,1,1,0,0],
       [0,0,1,0,0],
       [0,0,1,1,0],
       [0,0,0,0,0],
      ),
  );
my $num_pieces = scalar @pieces;

my @population;

for (my $i=0; $i<$population_size; $i++) {
  # an individual is an array (ref) of hashrefs, each with piece position info
  push @population, [ map {
			{
			  index => $_-1,
			  trans_x => int(rand($board_size-$max_piece_size)),
			  trans_y => int(rand($board_size-$max_piece_size)),
			  rotate => int(rand(4)),
		          flip => int(rand(2))
                        }
                      } (1 .. $num_pieces)
		    ];
}

# loop forever
my $generation = 0;
while (++$generation) {
  # sort the population by fitness (less negative the better - zero is best)
  my @fitnesses = map { my $fitness = evaluate_individual($_) } @population;
  my @sorted_indexes = sort { $fitnesses[$b] <=> $fitnesses[$a] } 0 .. $population_size-1;
  @population = @population[ @sorted_indexes ];


  # save an image of the best board so far
  my $fitness = $fitnesses[0];
  my $worst_fitness = evaluate_individual($population[$#population]);

  warn "generation\t$generation\tbest\t$fitness\tworst\t$worst_fitness\n";
  if ($generation % $output_frequency == 0 || $fitness == 0) {
    my $pdl = pretty_image($population[0]);
    $pdl->slice(":,-1:-$board_size")->wpic(sprintf "${prefix}_%05d_%d.png", $generation, $fitness);
  }

#  # and print out the instructions to build it!
#  my $best_indiv = $population[0];
#  open(OUT, ">best.txt");
#  foreach my $piece_info (@$best_indiv) {
#    my $piece = $pieces[$piece_info->{index}]->copy;
#    $piece = flip($piece) if $piece_info->{flip};
#    $piece = rotate90($piece) for (1..$piece_info->{rotate});
#    print OUT "$piece goes at $piece_info->{trans_x},$piece_info->{trans_y}\n\n";
#  }
#  close(OUT);

  last if ($fitness == 0); # hurray!

  # take the top X and make next generation
  my @next_population;
  while (@next_population < $population_size) {
    my $mate1 = splice(@population, int(rand($mating_from_best)), 1);
    my $mate2 = splice(@population, int(rand($mating_from_best)), 1);
    # mate them X times
    foreach (1 .. $mate_times) {
      push @next_population, mate($mate1, $mate2);
    }
  }

  @population = map { mutate($_) } @next_population;
}


#
# returns a single fitness value in scalar context
#
# returns (fitness, board) in array context
#
sub evaluate_individual {
  my ($individual, $greyscale) = @_;
  my $board = zeroes($board_size, $board_size);

  # add all the pieces to an empty board
  foreach my $piece_info (@$individual) {
    my ($x1, $x2) = ($piece_info->{trans_x}, $piece_info->{trans_x}+$max_piece_size-1);
    my ($y1, $y2) = ($piece_info->{trans_y}, $piece_info->{trans_y}+$max_piece_size-1);
    my $piece = $pieces[$piece_info->{index}]->copy;
    $piece = flip($piece) if $piece_info->{flip};
    $piece = rotate90($piece) for (1..$piece_info->{rotate});
    $board->slice("$x1:$x2,$y1:$y2") += $piece;
  }

  # now calculate the fitness

  # find a bounding box
  my $x_summary = $board->mv(-1,0)->maximum;
  my ($xmin, $xmax) = minmax(which($x_summary>0));
  my $y_summary = $board->maximum;
  my ($ymin, $ymax) = minmax(which($y_summary>0));

  # sum up offending cells withing the bbox
  my $bbox = $board->slice("$xmin:$xmax,$ymin:$ymax");
  # warn "bbox $xmin:$xmax,$ymin:$ymax\n" if (wantarray);
  my $gaps = sum($bbox==0);
  my $overlaps = sum($bbox>1);
  my $fitness = -1*$gaps - 100*$overlaps;

  return wantarray ? ($fitness, $board) : $fitness;
}

#
# returns a board with each pieces shaded differently
#
sub pretty_image {
  my ($individual) = @_;
  my $board = zeroes($board_size, $board_size);

  # add all the pieces to an empty board
  my $shade = @$individual/2;
  foreach my $piece_info (@$individual) {
    my ($x1, $x2) = ($piece_info->{trans_x}, $piece_info->{trans_x}+$max_piece_size-1);
    my ($y1, $y2) = ($piece_info->{trans_y}, $piece_info->{trans_y}+$max_piece_size-1);
    my $piece = $pieces[$piece_info->{index}]->copy;
    $piece = flip($piece) if $piece_info->{flip};
    $piece = rotate90($piece) for (1..$piece_info->{rotate});
    $board->slice("$x1:$x2,$y1:$y2") += $piece * $shade;
    $shade++;
  }
  return $board;
}

#
# returns two child objects
#

sub mate {
  my ($mate1, $mate2) = @_;
  my ($child1, $child2) = ([], []);
  for (my $i=0; $i<$num_pieces; $i++) {
    # pick a random assortment for each gene
    rand(2)>1 ? ( ($child1->[$i], $child2->[$i]) = ({ %{$mate1->[$i]} }, { %{$mate2->[$i]} }) )
      : ( ($child2->[$i], $child1->[$i]) = ({ %{$mate1->[$i]} }, { %{$mate2->[$i]} }) );

  }
  return $child1, $child2;
}

#
# returns a modified object
#

sub mutate {
  my ($indiv) = @_;
  my $mut_types = 4;
  for (my $i=0; $i<$num_pieces; $i++) {
    my $piece_info = $indiv->[$i];

    while (rand(1) < $mutation_rate) {
      if (rand(1) < 1/$mut_types) {
	$piece_info->{trans_x} += int(rand(7))-3;
	$piece_info->{trans_x} = 0 if ($piece_info->{trans_x} < 0);
	$piece_info->{trans_x} = $board_size-$max_piece_size-1 if ($piece_info->{trans_x} > $board_size-$max_piece_size-1);
      }
      if (rand(1) < 1/$mut_types) {
	$piece_info->{trans_y} += int(rand(7))-3;
	$piece_info->{trans_y} = 0 if ($piece_info->{trans_y} < 0);
	$piece_info->{trans_y} = $board_size-$max_piece_size-1 if ($piece_info->{trans_y} > $board_size-$max_piece_size-1);
      }
      if (rand(1) < 1/$mut_types) {
	$piece_info->{rotation} += int(rand(4));
      }
      if (rand(1) < 1/$mut_types) {
	$piece_info->{flip} += int(rand(2));
      }
    }

  }
  return $indiv;
}


sub flip {
  my $pdl = shift;
  return $pdl->slice("-1:-$max_piece_size");
}

sub rotate90 {
  my $pdl = shift;
  return flip($pdl)->transpose;
}
