package Podcast::UploadManager;
@ISA = qw( Podcast::LoggerInterface );

use Net::FTP;

$VERSION="0.30";

sub new { 
    my $class = shift;
    my $self = {};
    bless ( $self, $class );
    return $self;
}

sub init {
    my $self = shift;
    my $attr = shift;
    $self->{ 'host' } = $attr->{ 'host' } || $attr->{ 'hostname' };
    $self->{ 'username' } = $attr->{ 'username' };
    $self->{ 'password' } = $attr->{ 'password' };
    $self->{ 'path' } = $attr->{ 'path' };
    $self->{ 'protocol' } = $attr->{ 'protocol' } || 'ftp';    
    $self->{ 'remote_root' } = $attr->{ 'remote_root' };
    $self->{ 'remote_root' } .= "/" unless $self->{ 'remote_root' } =~ /\/$/;
}

sub DESTROY { 
    my $self = shift;
    $self->{ 'ftp_handle' }->quit if $self->{ 'ftp_handle' };
    $self->{ 'ftp_handle' } = 0;
}


sub upload {
    my $self = shift;
    my $file = shift;
    my $short_name = $1 if $file =~ /\/([^\/]+)$/;
    my $return_value = 0;

    if( $self->{ 'protocol' } eq 'ftp' ) {
	# Create ftp object if not there
	use Net::FTP;
	$self->{ 'ftp_handle' } = new Net::FTP( $self->{ 'host' } ) 
	    unless $self->{ 'ftp_handle' };
	my $ftp = $self->{ 'ftp_handle' };

	if( $ftp ) {
	    $ftp->login( $self->{ 'username' }, $self->{ 'password' } );
	    $ftp->cwd( $self->{ 'path' } );
	    $ftp->binary();

	    my $size = -s $file;
	    $return_value = $self->upload_if_necessary( $ftp, $short_name, $file );

	    # Disabled for now, sizes seem different regardless, bytes might be 
	    # incorrectly reported.
	    if( 0 && $self->{ 'remote_root' } ) {
		# Verify the file is there
		use LWP::Simple;
		my $full_path = $self->{ 'remote_root' } . $short_name;
		my @result = head( $full_path );
		$self->log_error( "Remote size ($result[1] vs $size) and local sizes are " .
				  "different [$full_path]" )
		    unless $result[ 1 ] == $size;
	    }
	}
    }
    return $return_value;
}

sub upload_if_necessary {

    my $self = shift;
    my $ftp = shift;
    my $short_name = shift;
    my $file = shift;
    my $return_value = 0;
    
    my $skip_upload = 0;
    # Get the message hash, to be sure.
    my $remote_digest_filename = "/tmp/" . $short_name . ".md5";
    $ftp->get( $short_name . ".md5", $remote_digest_filename );

    # OK, got remote digest, now check local one
    $ctx = Digest::MD5->new;
    if( open FILE, $file ) {
	$ctx->addfile( *FILE );
    }
    $local_digest = $ctx->hexdigest;
    
    my $remote_digest;
    if( -e $remote_digest_filename ) {
	# Read in the local remote digest, to compare
	$fh = new IO::File;
	if( $fh->open("< $remote_digest_filename") ) {
	    $remote_digest = <$fh>;
	    $fh->close;
	}
	# $self->log_message( "Hash: $remote_digest" );;
    }
    
    # Now, use the same filename to write the new digest
    my $fh = new IO::File;
    if( $fh->open( "> $remote_digest_filename" ) ) {
	print $fh $local_digest;
	$fh->close();
	# $self->log_message( "Wrote new digest: $local_digest" );
    }	
    
    if( $local_digest eq $remote_digest ) {
	$skip_upload = 1;
    }
    else {
	$self->log_message( "MD5 hashes ($local_digest vs $remote_digest)" );
    }

    if( not $skip_upload ) {
	$self->log_message( "Uploading $file and $remote_digest_filename" );
	if( $ftp->put( $file ) and
	    $ftp->put( $remote_digest_filename ) ) {
	    $return_value = 1;
	    $self->log_message( "Uploaded $file and $remote_digest_filename" );
	}
	else {
	    $self->log_error( "Unable to upload $file and $remote_digest_filename" );
	}
    }
    else { 
	# $self->log_message( "MD5 matches" );
	$return_value = 1;
    }

    return $return_value;
    
}


1;
