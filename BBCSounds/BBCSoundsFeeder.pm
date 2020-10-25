package Plugins::BBCSounds::BBCSoundsFeeder;

use warnings;
use strict;

use URI::Escape;

use Slim::Utils::Log;
use Slim::Networking::Async::HTTP;
use JSON::XS::VersionOneAndTwo;
use POSIX qw(strftime);
use HTTP::Date;

use Data::Dumper;

use Plugins::BBCSounds::BBCIplayerCompatability;
use Plugins::BBCSounds::SessionManagement;
use Plugins::BBCSounds::ActivityManagement;

my $log = logger('plugin.bbcsounds');

sub toplevel {
    my ( $client, $callback, $args ) = @_;
    $log->debug("++toplevel");

    my $menu;
    my $editorialTitle = "Our Daily Picks";
    $menu = [
        {
            name        => 'Search',
            type        => 'search',
            url         => \&getPage,
            passthrough => [ { type => 'search' } ],
            order       => 1,
        },
        {
            name        => 'Featured Podcasts & More',
            type        => 'link',
            url         => \&getPage,
            passthrough => [ { type => 'editorial' } ],
            order       => 3,
        },
        {
            name        => 'Music Mixes',
            type        => 'link',
            url         => \&getSubMenu,
            passthrough => [ { type => 'mixes' } ],
            order       => 5,
        },
        {
            name        => 'My Sounds',
            type        => 'link',
            url         => \&getSubMenu,
            passthrough => [ { type => 'mysounds' } ],
            order       => 2,
        },
        {
            name        => 'Recommended For You',
            type        => 'link',
            url         => \&getPersonalisedPage,
            passthrough => [ { type => 'recommended' } ],
            order       => 6,
        },
        {
            name        => 'Station Schedules',
            type        => 'link',
            url         => \&getPage,
            passthrough => [ { type => 'stationlist' } ],
            order       => 7,
        },
        {
            name        => 'Browse Categories',
            type        => 'link',
            url         => \&getSubMenu,
            passthrough => [ { type => 'categories' } ],
            order       => 7,
        }

    ];
 
    #Obtain the variable editorial content title

    my $fetch;
    my $callurl = 'https://rms.api.bbc.co.uk/v2/collections/p07fz59r/container';

    $fetch = sub {

        $log->debug("fetching: $callurl");

        Slim::Networking::SimpleAsyncHTTP->new(
            sub {
                my $http = shift;
                $editorialTitle = _parseEditorialTitle( $http->contentRef );
                push @$menu,
                  {
                    name        => $editorialTitle,
                    type        => 'link',
                    url         => \&getPage,
                    passthrough => [ { type => 'daily' } ],
                    order       => 4,
                  };
                @$menu = sort { $a->{order} <=> $b->{order} } @$menu;
                $callback->($menu);
            },

            # Called when no response was received or an error occurred.
            sub {
                $log->warn("error: $_[1]");
                push @$menu,
                  {
                    name        => $editorialTitle,
                    type        => 'link',
                    url         => \&getPage,
                    passthrough => [ { type => 'daily' } ],
                    order       => 4,
                  };

                #sort the list by order
                @$menu = sort { $a->{order} <=> $b->{order} } @$menu;
                $callback->($menu);
            },
            { cache => 1, expires => '1h' }
        )->get($callurl);
    };

    $fetch->();

    $log->debug("--toplevel");
    return;
}

sub getPage {
    my ( $client, $callback, $args, $passDict ) = @_;
    $log->debug("++getPage");

    my $menuType    = $passDict->{'type'};
    my $callurl     = "";
    my $denominator = "";

    if ( $menuType eq 'stationlist' ) {
        $callurl = 'https://rms.api.bbc.co.uk/v2/experience/inline/stations';
    }
    elsif ( $menuType eq 'editorial' ) {
        $callurl =
          'https://rms.api.bbc.co.uk/v2/experience/inline/listen/sign-in';
    }
    elsif ( $menuType eq 'daily' ) {
        $callurl =
'https://rms.api.bbc.co.uk/v2/collections/p07fz59r/members/playable?experience=domestic';
    }
    elsif ( $menuType eq 'tleo' ) {
        $callurl = 'https://rms.api.bbc.co.uk/v2/programmes/items?'
          . $passDict->{'filter'}
          . '&offset=' . $passDict->{'offset'};
        $denominator = "";
    }
    elsif ( $menuType eq 'container' ) {
        $callurl =
            'https://rms.api.bbc.co.uk/v2/programmes/playable?category='
          . $passDict->{'category'}
          . '&sort=-release_date'
          . '&offset=' . $passDict->{'offset'};
        $denominator = $passDict->{'category'};
    }
    elsif ( $menuType eq 'search' ) {
        my $searchstr = URI::Escape::uri_escape_utf8( $args->{'search'} );
        $callurl =
            'https://rms.api.bbc.co.uk/v2/experience/inline/search?q='
          . $searchstr
          . '&format=suggest';
    }
    elsif ( $menuType eq 'mixes' ) {
        $callurl =
            'https://rms.api.bbc.co.uk/v2/tagged/'
          . $passDict->{'tag'}
          . '/playable?experience=domestic';
    }
    elsif ( $menuType eq 'categories' ) {
        $callurl = 'https://rms.api.bbc.co.uk/v2/categories/container?kind='
          . $passDict->{'categorytype'};
    }
    elsif ( $menuType eq 'stationsdayschedule' ) {
        $callurl =
            'https://rms.api.bbc.co.uk/v2/experience/inline/schedules/'
          . $passDict->{'stationid'} . '/'
          . $passDict->{'scheduledate'};
    }
    else { $log->error("Invalid menu selection"); }
    my $menu = [];
    my $fetch;

    $fetch = sub {

        $log->debug("fetching: $callurl");

        Slim::Networking::SimpleAsyncHTTP->new(
            sub {
                my $http = shift;
                _parse( $http, $menuType, $menu, $denominator, $passDict );
                $callback->( { items => $menu } );
            },

            # Called when no response was received or an error occurred.
            sub {
                $log->warn("error: $_[1]");
                $callback->( [ { name => $_[1], type => 'text' } ] );
            },
            { cache => 1, expires => '1h' }
        )->get($callurl);
    };

    $fetch->();

    $log->debug("--getPage");
    return;
}

sub getScheduleDates {
    my ( $client, $callback, $args, $passDict ) = @_;
    $log->debug("++getScheduleDates");

    my $now       = time();
    my $stationid = $passDict->{'stationid'};
    my $menu      = [];

    for ( my $i = 0 ; $i < 30 ; $i++ ) {
        my $d = '';
        my $epoch = $now - ( 86400 * $i );
        if ( $i == 0 ) {
            $d = 'Today';
        }
        elsif ( $i == 1 ) {
            $d = 'Yesterday (' . strftime( '%A', localtime($epoch) ) . ')';
        }
        else {
            $d = strftime( '%A %d/%m/%Y', localtime($epoch) );
        }

        my $scheduledate = strftime( '%Y-%m-%d', localtime($epoch) );

        push @$menu,
          {
            name        => $d,
            type        => 'link',
            url         => \&getPage,
            passthrough => [
                {
                    type         => 'stationsdayschedule',
                    stationid    => $stationid,
                    scheduledate => $scheduledate
                }
            ],
          };

    }
    $callback->( { items => $menu } );
    $log->debug("--getScheduleDates");
    return;
}

sub getPersonalisedPage {
    my ( $client, $callback, $args, $passDict ) = @_;
    $log->debug("++getPersonalisedPage");

    my $menuType = $passDict->{'type'};
    my $callurl  = "";

    if (   ( $menuType eq 'bookmarks' )
        || ( $menuType eq 'latest' )
        || ( $menuType eq 'subscribed' ) )
    {
        $callurl = 'https://rms.api.bbc.co.uk/v2/my/experience/inline/sounds';
    }
    elsif ( $menuType eq 'recommended' ) {
        $callurl = 'https://rms.api.bbc.co.uk/v2/my/experience/inline/listen';
    }

    my $menu        = [];
    my $denominator = '';

    Plugins::BBCSounds::SessionManagement::renewSession(
        sub {
            $log->debug("fetching: $callurl");

            Slim::Networking::SimpleAsyncHTTP->new(
                sub {
                    my $http = shift;
                    _parse( $http, $menuType, $menu, $denominator );
                    $callback->( { items => $menu } );
                },
                sub {
                    # Called when no response was received or an error occurred.

                    $log->warn("error: $_[1]");
                    $callback->( [ { name => $_[1], type => 'text' } ] );
                }

            )->get($callurl);
        },

        #could not get a session
        sub {
            $menu = [ { name => 'Failed! - Could not get session' } ];
            $callback->( { items => $menu } );
        }
    );

    $log->debug("--getPersonalisedPage");
    return;
}

sub getJSONMenu {
    my ( $client, $callback, $args, $passDict ) = @_;
    $log->debug("++getJSONMenu");

    my $menu     = [];
    my $menuType = $passDict->{'type'};
    my $jsonData = $passDict->{'json'};

    if ( $menuType eq 'playable' ) {
        _getPlayableItemMenu( $jsonData, $menu );
        $callback->( { items => $menu } );
    }

    $log->debug("--getJSONMenu");
    return;
}

sub getSubMenu {
    my ( $client, $callback, $args, $passDict ) = @_;
    $log->debug("++getSubMenu");

    my $menuType = $passDict->{'type'};

    my $menu = [];

    if ( $menuType eq 'categories' ) {
        $menu = [
            {
                name => 'Browse all Music',
                type => 'link',
                url  => \&getPage,
                passthrough =>
                  [ { type => 'categories', categorytype => 'music' } ],
            },
            {
                name => 'Browse all Speech',
                type => 'link',
                url  => \&getPage,
                passthrough =>
                  [ { type => 'categories', categorytype => 'speech' } ],
            }
        ];
    }
    elsif ( $menuType eq 'mysounds' ) {
        $menu = [
            {
                name        => 'Latest',
                type        => 'link',
                url         => \&getPersonalisedPage,
                passthrough => [ { type => 'latest' } ],
            },
            {
                name        => 'Bookmarks',
                type        => 'link',
                url         => \&getPersonalisedPage,
                passthrough => [ { type => 'bookmarks' } ],
            },
            {
                name        => 'Subscribed',
                type        => 'link',
                url         => \&getPersonalisedPage,
                passthrough => [ { type => 'subscribed' } ],
            }

        ];
    }
    elsif ( $menuType eq 'mixes' ) {
        $menu = [
            {
                name => 'Fresh New Music',
                type => 'link',
                url  => \&getPage,
                passthrough =>
                  [ { type => 'mixes', tag => 'fresh_new_music' } ],
            },
            {
                name        => 'Music to Chill to',
                type        => 'link',
                url         => \&getPage,
                passthrough => [ { type => 'mixes', tag => 'chill' } ],
            },
            {
                name => 'Dance Music',
                type => 'link',
                url  => \&getPage,
                passthrough =>
                  [ { type => 'mixes', tag => 'dance', page => '1' } ],
            },
            {
                name        => 'Feel Good Tunes',
                type        => 'link',
                url         => \&getPage,
                passthrough => [
                    { type => 'mixes', tag => 'feel_good_tunes', page => '1' }
                ],
            },
            {
                name => 'Music to Focus to',
                type => 'link',
                url  => \&getPage,
                passthrough =>
                  [ { type => 'mixes', tag => 'focus', page => '1' } ],
            },
            {
                name => 'Greatest Hits',
                type => 'link',
                url  => \&getPage,
                passthrough =>
                  [ { type => 'mixes', tag => 'greatest_hits', page => '1' } ],
            },
        ];
    }

    $callback->( { items => $menu } );
    $log->debug("--getSubMenu");
    return;
}

sub initSignin {
    my ( $client, $callback, $args, $passDict ) = @_;
    $log->debug("++initSignin");
    my $menu = [];

    Plugins::BBCSounds::SessionManagement::signIn(
        sub {

            $log->debug("Sign In Succeeded");
            $menu = [
                {
                    name => 'Sign In Succeeded'
                }
            ];
            $callback->( { items => $menu } );
        },
        sub {

            $log->debug("Sign In Failed");
            $menu = [
                {
                    name => 'Sign In Failed'
                }
            ];
            $callback->( { items => $menu } );
        }
    );
    $log->debug("--initSignin");
    return;
}

sub initSignout {
    my ( $client, $callback, $args, $passDict ) = @_;
    $log->debug("++initSignout");
    my $menu = [];

    Plugins::BBCSounds::SessionManagement::signOut(
        sub {

            $log->debug("Sign Out Succeeded");
            $menu = [
                {
                    name => 'Sign Out Succeeded'
                }
            ];
            $callback->( { items => $menu } );
        },
        sub {

            $log->debug("Sign Out Failed");
            $menu = [
                {
                    name => 'Sign Out Failed'
                }
            ];
            $callback->( { items => $menu } );
        }
    );
    $log->debug("--initSignout");
    return;
}

sub _parse {
    my $http        = shift;
    my $optstr      = shift;
    my $menu        = shift;
    my $denominator = shift;
    my $passthrough = shift;
    $log->debug("++parse");

    if ( $optstr eq 'live' ) {
        _parseLiveStations( $http->contentRef, $menu );
    }
    elsif ( $optstr eq 'daily' ) {
        my $JSON = decode_json ${ $http->contentRef };
        _parseItems( $JSON->{data}, $menu );
    }
    elsif ( $optstr eq 'editorial' ) {
        my $JSON = decode_json ${ $http->contentRef };
        _parseItems( _getDataNode( $JSON->{data}, 'priority_brands' ), $menu );
    }
    elsif ( $optstr eq 'search' ) {
        my $JSON = decode_json ${ $http->contentRef };
        _parseItems( _getDataNode( $JSON->{data}, 'container_search' ), $menu );
        _parseItems( _getDataNode( $JSON->{data}, 'playable_search' ),  $menu );
    }
    elsif ( $optstr eq 'mixes' ) {
        my $JSON = decode_json ${ $http->contentRef };
        _parseItems( $JSON->{data}, $menu );
    }
    elsif ( $optstr eq 'tleo' ) {
        my $JSON = decode_json ${ $http->contentRef };
        _parseItems( $JSON->{data}, $menu );
        _createOffset( $JSON, $passthrough, $menu );
    }
    elsif ( $optstr eq 'container' ) {
        my $JSON = decode_json ${ $http->contentRef };
        _parseItems( $JSON->{data}, $menu );
        _createOffset( $JSON, $passthrough, $menu );
    }
    elsif ( $optstr eq 'categories' || $optstr eq 'catitem' ) {
        _parseCategories( $http->contentRef, $menu );
    }
    elsif ( $optstr eq 'latest' ) {
        my $JSON = decode_json ${ $http->contentRef };
        _parseItems( _getDataNode( $JSON->{data}, 'latest' ), $menu );
    }
    elsif ( $optstr eq 'bookmarks' ) {
        my $JSON = decode_json ${ $http->contentRef };
        _parseItems( _getDataNode( $JSON->{data}, 'favourites' ), $menu );
    }
    elsif ( $optstr eq 'subscribed' ) {
        my $JSON = decode_json ${ $http->contentRef };
        _parseItems( _getDataNode( $JSON->{data}, 'follows' ), $menu );
    }
    elsif ( $optstr eq 'recommended' ) {
        my $JSON = decode_json ${ $http->contentRef };
        _parseItems( _getDataNode( $JSON->{data}, 'recommendations' ), $menu );
    }
    elsif ( $optstr eq 'stationlist' ) {
        my $JSON = decode_json ${ $http->contentRef };
        _parseStationlist( _getDataNode( $JSON->{data}, 'promoted_stations' ),
            $menu );
        _parseStationlist( _getDataNode( $JSON->{data}, 'local_stations' ),
            $menu );
    }
    elsif ( $optstr eq 'stationsdayschedule' ) {
        my $JSON = decode_json ${ $http->contentRef };
        _parseItems( _getDataNode( $JSON->{data}, 'schedule_items' ), $menu );
    }

    else { $log->error("Invalid BBC HTML Parse option"); }

    $log->debug("--parse");
    return;
}

sub _getDataNode {
    my $json = shift;
    my $id   = shift;
    $log->debug("--_getDataNode");

    my $item = [];

    for my $top (@$json) {
        if ( $top->{id} eq $id ) {
            $item = $top->{data};
        }
    }
    $log->debug("--_getDataNode");
    return $item;
}

sub _parseItems {
    my $jsonData = shift;
    my $menu     = shift;
    $log->debug("++_parseItems");
    my $size = scalar @$jsonData;

    $log->info("Number of items : $size ");

    for my $item (@$jsonData) {

        if ( $item->{type} eq 'playable_item' ) {
            _parsePlayableItem( $item, $menu );
        }
        elsif ( $item->{type} eq 'container_item' ) {
            _parseContainerItem( $item, $menu );
        }
        elsif ( $item->{type} eq 'broadcast_summary' ) {
            _parseBroadcastItem( $item, $menu );
        }
    }
    $log->debug("--_parseItems");
    return;
}

sub _parseStationlist {
    my $jsonData = shift;
    my $menu     = shift;
    $log->debug("++_parseStationlist");
    my $size = scalar @$jsonData;

    $log->debug( 'dump' . Dumper($jsonData) );

    $log->info("Number of items : $size ");

    for my $item (@$jsonData) {
        my $image =
            'http://radio-service-information.api.bbci.co.uk/logos/'
          . _getPidfromSoundsURN( $item->{urn} )
          . '/128x128.png';
        push @$menu,
          {
            name => $item->{network}->{short_title},
            type => 'link',
            icon => $image,
            url  => \&getScheduleDates,
            passthrough =>
              [ { type => 'stationschedule', stationid => $item->{id} } ],
          };
    }
    $log->debug("--_parseStationlist");
    return;
}

sub _parsePlayableItem {
    my $item = shift;
    my $menu = shift;
    $log->debug("++_parsePlayableItem");

    my $title1 = $item->{titles}->{primary};
    my $title2 = $item->{titles}->{secondary};
    my $title3 = $item->{synopses}->{short};

    my $title = $title1 . ' - ' . $title2 . ' -' . $item->{release}->{label};
    my $pid   = _getPidfromSoundsURN( $item->{urn} );

    my $iurl = $item->{image_url};
    my $image =
      Plugins::BBCSounds::BBCIplayerCompatability::createIplayerIcon(
        ( _getPidfromImageURL($iurl) ) );

    push @$menu,
      {
        name        => $title,
        type        => 'link',
        icon        => $image,
        url         => \&getJSONMenu,
        passthrough => [ { type => 'playable', json => $item } ],
      };
}

sub _parseBroadcastItem {
    my $item = shift;
    my $menu = shift;
    $log->debug("++_parseBroadcastItem");

    my $title1 = $item->{titles}->{primary};
    my $title2 = $item->{titles}->{secondary};
    my $title3 = $item->{synopses}->{short};

    my $sttim = str2time( $item->{'start'} );
    my $sttime = strftime( '%H:%M ', localtime($sttim) );

    my $title = $sttime . $title1 . ' - ' . $title2;

    my $iurl = $item->{image_url};
    my $image =
      Plugins::BBCSounds::BBCIplayerCompatability::createIplayerIcon(
        ( _getPidfromImageURL($iurl) ) );

    push @$menu,
      {
        name        => $title,
        type        => 'link',
        icon        => $image,
        url         => \&getJSONMenu,
        passthrough => [ { type => 'playable', json => $item } ],
      };

    $log->debug("--_parseBroadcastItem");
    return;
}

sub _createOffset {
    my $json       = shift;
    my $passthrough = shift;
    my $menu = shift;
    
    $log->debug("++_createOffset");

    if ( defined $json->{offset} ) {
        my $offset = $json->{offset};
        my $total  = $json->{total};
        my $limit  = $json->{limit};
        
              
        if ( ( $offset + $limit ) < $total ) {
            my $nextstart = $offset + $limit + 1;
            my $nextend   = $nextstart + $limit;
            if ( ( $limit + $nextstart ) > $total ) { $nextend = $total; }
            my $title = 'Next - ' . $nextstart . ' to ' . ($nextend-1) . ' of ' . $total;
                                   
            $passthrough->{'offset'} = ($nextstart - 1);
            
            push @$menu,
              {
                name        => $title,
                type        => 'link',
                url         => \&getPage,
                passthrough => [$passthrough],
              };
              
        }
    }
    $log->debug("--_createOffset");
    return;
}

sub _parseContainerItem {
    my $podcast = shift;
    my $menu    = shift;
    $log->debug("++_parseContainerItem");

    my $title = $podcast->{titles}->{primary};
    my $desc  = $podcast->{synopses}->{short};

    my $pid = $podcast->{id};

    my $image =
      Plugins::BBCSounds::BBCIplayerCompatability::createIplayerIcon(
        _getPidfromImageURL( $podcast->{image_url} ) );

    push @$menu,
      {
        name => $title . ' - ' . $desc,
        type => 'link',
        icon => $image,
        url  => \&getPage,
        passthrough =>
          [ { type => 'tleo', filter => 'container=' . $pid, offset => 0 } ],
      };

    $log->debug("--_parseContainerItem");
    return;
}

sub _parseCategories {
    my $htmlref = shift;
    my $menu    = shift;
    $log->debug("++_parseCategories");

    my $catJSON = decode_json $$htmlref;
    my $results = $catJSON->{data};

    my $size = scalar @$results;

    $log->info("Number of cats : $size ");

    for my $cat (@$results) {
        my $children = $cat->{child_categories};
        my $title    = $cat->{titles}->{primary};
        my $image =
          Plugins::BBCSounds::BBCIplayerCompatability::createIplayerIcon(
            _getPidfromImageURL( $cat->{image_url} ) );
        push @$menu,
          {
            name => $title,
            type => 'link',
            icon => $image,
            url  => \&getPage,
            passthrough =>
              [ { type => 'container', category => $cat->{id}, offset => 0 } ],
          };

    }
    $log->debug("--_parseCategories");
    return;
}

sub _getPidfromImageURL {
    my $url = shift;
    $log->debug("++_getPidfromImageURL");

    $log->debug("url to create pid : $url");
    my @pid = split /\//x, $url;
    my $pid = pop(@pid);
    $pid = substr $pid, 0, -4;

    $log->debug("--_getPidfromImageURL - $pid");
    return $pid;
}

sub _getPidfromSoundsURN {
    my $urn = shift;
    $log->debug("++_getPidfromSoundsURN");

    $log->debug("urn to create pid : $urn");
    my @pid = split /:/x, $urn;
    my $pid = pop(@pid);

    $log->debug("--_getPidfromSoundsURN - $pid");
    return $pid;
}

sub _parseEditorialTitle {
    my $htmlref = shift;
    $log->debug("++_parseEditorialTitle");

    my $edJSON = decode_json $$htmlref;
    my $title =
      $edJSON->{titles}->{primary} . ' - ' . $edJSON->{synopses}->{short};

    $log->debug("--_parseEditorialTitle - $title");
    return $title;
}

sub _getPlayableItemMenu {
    my $item = shift;
    my $menu = shift;
    $log->debug("++_getPlayableItemMenu");

    my $urn = $item->{urn};
    my $pid = _getPidfromSoundsURN( $item->{urn} );

    push @$menu,
      {
        name => 'Play',
        url  => \&Plugins::BBCSounds::BBCIplayerCompatability::handlePlaylist,
        passthrough => [ { pid => $pid } ],
        type        => 'playlist',
        on_select   => 'play',
      };

    push @$menu,
      {
        name        => 'Bookmark',
        type        => 'link',
        url         => \&Plugins::BBCSounds::ActivityManagement::createActivity,
        passthrough => [ { activitytype => 'bookmark', urn => $urn } ],
      };

    if ( defined $item->{container}->{id} ) {
        push @$menu,
          {
            name => 'Subscribe',
            type => 'link',
            url  => \&Plugins::BBCSounds::ActivityManagement::createActivity,
            passthrough => [
                {
                    activitytype => 'subscribe',
                    urn          => $item->{container}->{urn}
                }
            ],
          };
        push @$menu, {
            name        => 'All Episodes',
            type        => 'link',
            url         => \&getPage,
            passthrough => [
                {
                    type   => 'tleo',
                    filter => 'container=' . $item->{container}->{id},
                    offset => 0,
                }
            ],

        };
    }

    $log->debug("--_getPlayableItemMenu");
    return;
}

#Why does perl make you put this 1 at the end?  who knows?
1;
