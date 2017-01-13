#!/usr/bin/env perl
#          -*- mode: cperl -*-
#
use strict;
use warnings;
use PDL;
use PDL::IO::Pic;
use PDL::Image2D;
use Getopt::Long;

my $population_size = 5000;
my $mating_from_best = 500;
my $mate_times = 2; # should be an integer > 1
my $mutation_rate = 1/12; # probability (ish) per gene
my $board_size = 16;
my $max_piece_size = 5; # all pieces fit in 4x4 square
my $prefix = 'best';
my $output_frequency = 1; # save a PNG every N generations
my $neighbour_kernel = pdl([1,1,1],[1,0,1],[1,1,1]);
my $quiet; # only save best so far images and print no progress line

GetOptions(
	   "prefix=s"=>\$prefix,
	   "quiet"=>\$quiet,
	  );


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
my $best_fitness;
while (++$generation) {
  # sort the population by fitness (less negative the better - zero is best)
  my @fitnesses = map { evaluate_individual($_) } @population;
  my @sorted_indexes = sort { $fitnesses[$b] <=> $fitnesses[$a] } 0 .. $population_size-1;
  @population = @population[ @sorted_indexes ];

  my $fitness =  evaluate_individual($population[0]);
  my $worst_fitness = evaluate_individual($population[$#population]);

  warn "generation\t$generation\tbest\t$fitness\tworst\t$worst_fitness\n" unless ($quiet);

  my $new_best;
  if (!defined $best_fitness || $fitness > $best_fitness) {
    $best_fitness = $fitness;
    $new_best = 'true';
  }

  if ((!$quiet && $generation % $output_frequency == 0) || ($quiet && $new_best)) {
    # save an image of the best board this generation
    my $pdl = pretty_image($population[0]);
    $pdl->slice(":,-1:-$board_size")->wpic(sprintf "${prefix}_%05d_%d.png", $generation, $fitness);
  }

  # last if ($fitness == 0); # current fitness func doesn't go to zero

  # take the top X and make next generation
  my @next_population;
  while (@next_population < $population_size) {
    my $mate1 = splice(@population, int(rand($mating_from_best)), 1);
    my $mate2 = splice(@population, int(rand($mating_from_best)), 1);
    # mate them X times to make 2X offspring
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
  my ($individual) = @_;
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
  # my $bbox = $board->slice("$xmin:$xmax,$ymin:$ymax");
  # warn "bbox $xmin:$xmax,$ymin:$ymax\n";

  my $gaps = $board==0;
  my $neighbour_sums = $board->conv2d($neighbour_kernel, { Boundary=>'Default' }); # wrapping
  my $gap_neighbour_sums = $gaps*$neighbour_sums;

  my $overlaps = sum($board>1);

  my $fitness = -1*sum($gap_neighbour_sums*$gap_neighbour_sums) - 1000*$overlaps;

  return $fitness;
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
	$piece_info->{trans_x} += random_offset($board_size);
	# bounds checks have to 'teleport' otherwise edges become refuge from mutation
	$piece_info->{trans_x} = int(rand($board_size-$max_piece_size)) if ($piece_info->{trans_x} < 0);
	$piece_info->{trans_x} = int(rand($board_size-$max_piece_size)) if ($piece_info->{trans_x} > $board_size-$max_piece_size-1);
      }
      if (rand(1) < 1/$mut_types) {
	$piece_info->{trans_y} += random_offset($board_size);
	$piece_info->{trans_y} = int(rand($board_size-$max_piece_size)) if ($piece_info->{trans_y} < 0);
	$piece_info->{trans_y} = int(rand($board_size-$max_piece_size)) if ($piece_info->{trans_y} > $board_size-$max_piece_size-1);
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

sub random_offset {
  my $max = shift;
  my $direction = rand(1)<0.5 ? -1 : 1;
  return $direction*int(rand(1)*rand(1)*$max);
}
