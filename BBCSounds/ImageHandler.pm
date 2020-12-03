package Plugins::BBCSounds::ImageHandler;

use warnings;
use strict;




use Slim::Utils::Log;

my $log = logger('plugin.bbcsounds');


sub createBBCBrandImage {
    my $imageIn = shift;
    my $brandIn = shift;
    my $cbY = shift;
    my $cbN = shift;


    require Image::Magick;

	main::INFOLOG && $log->is_info && $log->info("Creating brand image using $imageIn");
    my $circle = Image::Magick->new(size=>'320x320');
    $circle->Set(matte=>'True');    
    $circle->Draw(fill=>'ffffff',primitive=>'circle', points=>'160,160 160,1');
    
    my $image = Image::Magick->new;
    $image->Read($imageIn);
    $image->Set(matte=>'True');
    $image->Composite(image=>$circle,compose=>'DstIn');

    my $ret = $image->Write(filename=>'plugins/BBCSounds/html/images/circle.png');

    main::INFOLOG && $log->is_info && $log->info("This happened $ret");

    undef $image;
    undef $circle;

}

1;
