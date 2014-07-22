package HTMLTidy::CMS;

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request::Common qw(POST);
use Encode;

sub _app_cms_preview_with_html_tidy {
    my $app = shift;
    my $blog = $app->blog;
    if (! $blog ) {
        return '';
    }
    require MT::CMS::Entry;
    $app->validate_magic or return;
    my $entry = MT::CMS::Entry::_create_temp_entry( $app );
    if (! $entry->authored_on ) {
        my $d = $app->param( 'authored_on_date' );
        my $t = $app->param( 'authored_on_time' );
        my $ts = $d . $t;
        $ts =~ s/[^0-9]//g;
        $entry->authored_on( $ts );
    }
    my $component = MT->component( 'HTMLTidy' );
    my $tmpl = $component->get_config_value( 'preview_template_for_tidy', 'blog:' . $blog->id );
    if (! $tmpl ) {
        my $_tmpl = File::Spec->catfile( $component->path, 'tmpl', 'preview.tmpl' );
        require MT::FileMgr;
        my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
        $tmpl = $fmgr->get_data( $_tmpl );
    }
    require MT::Template;
    my $template = MT::Template->new;
    $template->text( $tmpl );
    my $ctx = $template->context();
    $ctx->stash( 'blog', $blog );
    $ctx->stash( 'blog_id', $blog->id );
    $ctx->stash( 'entry', $entry );
    my %param;
    $param{ preview_template } = 1;
    my $preview_html = $app->build_page( $template, \%param );
    my $dialog = File::Spec->catfile( $component->path, 'tmpl', 'tidy.tmpl' );
    my $api = $component->get_config_value( 'tidy_api' );
    my $remote_ip = $app->remote_ip;
    my $user_agent ='Mozilla/5.0 (Movable Type HTMLTidy Plugin 0.1 X_FORWARDED_FOR:' . $remote_ip . ')';
    my %params = (
        html => utf8_off( $preview_html ),
        errors => 1,
        original => 1,
        responseType => 'JSON',
        with_anchor => 1,
        language => utf8_off( $app->user->preferred_language ),
    );
    my $request = POST( $api, [ %params ] );
    my $ua = LWP::UserAgent->new( agent => $user_agent );
    my $res = $ua->request( $request );
    my $json;
    if ( $res->is_success ) {
        $json = utf8_on( $res->content );
    }
    my $result = MT::Util::from_json( $json );
    my $original = $result->{ original };
    my $errors = $result->{ errors };
    my @errors_loop;
    for my $err ( @$errors ) {
        push( @errors_loop, { message => $err } );
    }
    $param{ errors_loop } = \@errors_loop;
    $param{ original } = $original;
    $param{ result } = $result->{ result };
    $app->build_page( $dialog, \%param );
}

sub _cb_edit_entry {
    my ( $cb, $app, $tmpl ) = @_;
    my $button = <<'MTML';
    <div class="tidy-action">
      <button
         name="tidy_entry"
         style="width:100%;margin-bottom:10px;"
         type="submit"
         id="tidy"
         class="action button mt-open-dialog"">
        <__trans phrase="HTML Tidy!">
      </button>
    </div>
<script>
/* <![CDATA[ */
    jQuery('#tidy').click(function(event) {
        // var _dialog = jQuery.fn.mtDialog.open('<mt:var name="script_url">?__mode=preview_with_html_tidy&amp;magic_token=<mt:var name="magic_token" escape="url">');
        // jQuery('form#entry_form').attr('target', 'mt-dialog-iframe');
        var orig_t = jQuery('form#entry_form').attr('target');
        jQuery('form#entry_form').attr('target', '_blank');
        jQuery('form#entry_form input[name=__mode]').val('preview_with_html_tidy');
        jQuery('form#entry_form').submit();
        jQuery('form#entry_form input[name=__mode]').val('save');
        if ( orig_t ) {
            jQuery('form#entry_form').attr('target', orig_t);
        } else {
            jQuery('form#entry_form').attr('target', '_self');
        }
        return false;
    });
/* ]]> */
</script>
MTML
    my $search = quotemeta( '<div class="actions-bar">' );
    $$tmpl =~ s/($search)/$button $1/s;
}

sub utf8_on {
    my $text = shift;
    if (! Encode::is_utf8( $text ) ) {
        Encode::_utf8_on( $text );
    }
    return $text;
}

sub utf8_off {
    my $text = shift;
    return MT::I18N::utf8_off( $text );
}

1;