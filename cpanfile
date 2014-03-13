requires 'perl', '5.018';

requires 'HTML::LinkExtor';
requires 'HTML::TableExtract';
requires 'HTTP::Request::Common';
requires 'LWP::UserAgent';
requires 'List::AllUtils';
requires 'Moo';
requires 'namespace::autoclean';
requires 'strictures';

feature 'server', 'Web API server' => sub {
    requires 'FindBin';
    requires 'JSON';
    requires 'JSON::XS';
    requires 'Plack::App::File';
    requires 'Plack::Middleware::ReverseProxy';
    requires 'Server::Starter';
    requires 'Starlet';
    requires 'Web::Simple';
};

on test => sub {
    requires 'Test::More', '0.88';
};
