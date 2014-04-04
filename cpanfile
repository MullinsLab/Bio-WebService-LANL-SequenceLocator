requires 'perl', '5.018';

requires 'HTML::LinkExtor';
requires 'HTML::TableExtract';
requires 'HTML::TokeParser';
requires 'HTTP::Request::Common';
requires 'LWP::UserAgent';
requires 'List::AllUtils';
requires 'Moo';
requires 'strictures';

feature 'server', 'Web API server' => sub {
    requires 'File::Share';
    requires 'JSON';
    requires 'JSON::XS';
    requires 'Plack::App::File';
    requires 'Plack::Middleware::ReverseProxy';
    requires 'Plack::Middleware::CrossOrigin';
    requires 'Server::Starter';
    requires 'Starlet';
    requires 'Web::Simple';
};

on test => sub {
    requires 'Test::More', '0.88';
};
