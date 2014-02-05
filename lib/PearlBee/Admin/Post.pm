
=head

Author: Andrei Cacio
Email: andrei.cacio@evozon.com

=cut

package PearlBee::Admin::Post;

use Dancer2;
use Dancer2::Plugin::DBIC;

use String::Dirify;
use String::Util 'trim';
use Digest::SHA1 qw(sha1_hex);
use Time::HiRes qw(time);
use DateTime::Format::Strptime;
use POSIX qw(strftime);
use Cwd;

=head

list all posts method

=cut

get '/admin/posts' => sub {

    my @posts   = resultset('Post')->search( {}, { order_by => 'created_date DESC' } );
    my $publish = resultset('Post')->search( { status       => 'published' } )->count;
    my $trash   = resultset('Post')->search( { status       => 'trash' } )->count;
    my $draft   = resultset('Post')->search( { status       => 'draft' } )->count;
    my $all     = scalar(@posts);

    template '/admin/posts/list',
      {
        posts   => \@posts,
        trash   => $trash,
        draft   => $draft,
        publish => $publish,
        all     => $all
      },
      { layout => 'admin' };
};

=head

list all published posts

=cut

get '/admin/posts/published' => sub {

    my @posts = resultset('Post')->search( { status => 'published' }, { order_by => 'created_date DESC' } );

    my $all   = resultset('Post')->search( { 1      => '1' } )->count;
    my $trash = resultset('Post')->search( { status => 'trash' } )->count;
    my $draft = resultset('Post')->search( { status => 'draft' } )->count;
    my $publish = scalar(@posts);

    template '/admin/posts/list',
      {
        posts   => \@posts,
        trash   => $trash,
        draft   => $draft,
        publish => $publish,
        all     => $all
      },
      { layout => 'admin' };
};

=head

list all draft posts

=cut

get '/admin/posts/draft' => sub {

    my @posts = resultset('Post')->search( { status => 'draft' }, { order_by => 'created_date DESC' } );

    my $all     = resultset('Post')->search( { 1      => '1' } )->count;
    my $trash   = resultset('Post')->search( { status => 'trash' } )->count;
    my $publish = resultset('Post')->search( { status => 'published' } )->count;
    my $draft   = scalar(@posts);

    template '/admin/posts/list',
      {
        posts   => \@posts,
        trash   => $trash,
        draft   => $draft,
        publish => $publish,
        all     => $all
      },
      { layout => 'admin' };
};

=head

list all trash posts

=cut

get '/admin/posts/trash' => sub {

    my @posts = resultset('Post')->search( { status => 'trash' }, { order_by => 'created_date DESC' } );

    my $all     = resultset('Post')->search( { 1      => '1' } )->count;
    my $publish = resultset('Post')->search( { status => 'published' } )->count;
    my $draft   = resultset('Post')->search( { status => 'draft' } )->count;
    my $trash   = scalar(@posts);

    template '/admin/posts/list',
      {
        posts   => \@posts,
        trash   => $trash,
        draft   => $draft,
        publish => $publish,
        all     => $all
      },
      { layout => 'admin' };
};

=head

publish method

=cut

get '/admin/posts/publish/:id' => sub {
    my $post_id = params->{id};

    my $post;
    eval {
        $post = resultset('Post')->find($post_id);
        $post->update( { status => 'published' } );
    };

    redirect '/admin/posts';
};

=head

draft method

=cut

get '/admin/posts/draft/:id' => sub {
    my $post_id = params->{id};

    my $post;
    eval {
        $post = resultset('Post')->find($post_id);
        $post->update( { status => 'draft' } );
    };

    redirect '/admin/posts';
};

=head

trash method

=cut

get '/admin/posts/trash/:id' => sub {
    my $post_id = params->{id};

    my $post;
    eval {
        $post = resultset('Post')->find($post_id);
        $post->update( { status => 'trash' } );
    };

    redirect '/admin/posts';
};

=head

add method

=cut

any '/admin/posts/add' => sub {

    my @categories = resultset('Category')->all();

    eval {
        # Generate a random string based on the current time and date
        my $t = time;
        my $date = strftime "%Y%m%d %H:%M:%S", localtime $t;
        $date .= sprintf ".%03d", ( $t - int($t) ) * 1000;    # without rounding
        $date = sha1_hex($date);

        # Upload the cover image
        my $cover;
        my $ext;
        if ( upload('cover') ) {
            $cover = upload('cover');
            ($ext) = $cover->filename =~ /(\.[^.]+)$/;        #extract the extension
            $ext = lc($ext);
        }
        $cover->copy_to( config->{covers_folder} . $date . $ext ) if $cover;

        # Save the post into the database
        my $user   = session('user');
        my $status = params->{status};
        my $post   = resultset('Post')->create(
            {
                title   => params->{title},
                content => params->{post},
                user_id => $user->id,
                status  => $status,
                cover   => $cover ? $date . $ext : '',
            }
        );

        # Connect the categories selected with the new post
        params->{category} = 1 if ( !params->{category} );    # If no category is selected the Uncategorized category will be stored default
        my @categories_selected = ref( params->{category} ) eq 'ARRAY' ? @{ params->{category} } : params->{category};    # Force an array if only one category was selected

        resultset('PostCategory')->create(
            {
                category_id => $_,
                post_id     => $post->id
            }
        ) foreach (@categories_selected);

        # Connect and update the tags table
        my @tags = split( ', ', params->{tags} );
        foreach my $tag (@tags) {

            # Replace all white spaces with hyphen
            my $slug = $tag;
            $slug = String::Dirify->dirify( trim($slug), '-' );    # Convert the string intro a valid slug

            my $db_tag = resultset('Tag')->find_or_create( { name => $tag, slug => $slug } );

            resultset('PostTag')->create(
                {
                    tag_id  => $db_tag->id,
                    post_id => $post->id
                }
            );
        }
    };

    error $@ if ($@);

    template '/admin/posts/add', { categories => \@categories }, { layout => 'admin' };
};

=head

edit method

=cut

get '/admin/posts/edit/:id' => sub {

    my $post_id         = params->{id};
    my $post            = resultset('Post')->find($post_id);
    my @post_categories = $post->post_categories;
    my @post_tags       = $post->post_tags;
    my @all_categories  = resultset('Category')->all;

    # Prepare tags for the UI
    my @tag_names;
    push( @tag_names, $_->tag->name ) foreach (@post_tags);
    my $joined_tags = join( ', ', @tag_names );

    # Prepare the categories
    my @categories;
    push( @categories, $_->category ) foreach (@post_categories);

    # Array of post categories id for populating the checkboxes
    my @categories_ids;
    push( @categories_ids, $_->id ) foreach (@categories);

    template '/admin/posts/edit',
      {
        post           => $post,
        tags           => $joined_tags,
        categories     => \@categories,
        all_categories => \@all_categories,
        ids            => \@categories_ids
      },
      { layout => 'admin' };

};

=head

update method

=cut

post '/admin/posts/update/:id' => sub {

    my $post_id = params->{id};
    my $title   = params->{title};
    my $content = params->{content};
    my $tags    = params->{tags};

    my $post = resultset('Post')->find($post_id);

    eval {
        # Upload the cover image
        my $cover;
        my $ext;
        my $date;

        if ( upload('cover') ) {

            # Generate a random string based on the current time and date
            my $t = time;
            $date = strftime "%Y%m%d %H:%M:%S", localtime $t;
            $date .= sprintf ".%03d", ( $t - int($t) ) * 1000;    # without rounding
            $date = sha1_hex($date);

            $cover = upload('cover');
            ($ext) = $cover->filename =~ /(\.[^.]+)$/;            #extract the extension
            $ext = lc($ext);
            $cover->copy_to( config->{covers_folder} . $date . $ext );
        }

        my $status = params->{status};
        $post->update(
            {
                title   => params->{title},
                cover   => ($date) ? $date . $ext : $post->cover,
                status  => $status,
                content => params->{post},
            }
        );

        # Reconnect the categories with the new one and delete the old ones
        my @post_categories = resultset('PostCategory')->search( { post_id => $post_id } );
        $_->delete foreach (@post_categories);

        my @categories = ref( params->{category} ) eq 'ARRAY' ? @{ params->{category} } : params->{category};    # Force an array if only one category was selected

        resultset('PostCategory')->create(
            {
                category_id => $_,
                post_id     => $post->id
            }
        ) foreach (@categories);

        # Reconnect and update the selected tags
        my @post_tags = resultset('PostTag')->search( { post_id => $post_id } );
        $_->delete foreach (@post_tags);

        my @tags = split( ',', params->{tags} );
        foreach my $tag (@tags) {
            my $slug = $tag;
            $slug = String::Dirify->dirify( trim($slug), '-' );    # Convert the string intro a valid slug

            my $db_tag = resultset('Tag')->find_or_create( { name => $tag, slug => $slug } );

            resultset('PostTag')->create(
                {
                    tag_id  => $db_tag->id,
                    post_id => $post->id
                }
            );
        }

    };

    error $@ if ($@);

    redirect '/admin/posts/edit/' . $post_id;

};

1;
