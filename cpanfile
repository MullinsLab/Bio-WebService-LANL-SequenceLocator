requires 'FindBin';
requires 'HTTP::Request::Common';
requires 'JSON';
requires 'JSON::XS';
requires 'List::AllUtils';
requires 'LWP::UserAgent';
requires 'Plack::App::File';
requires 'URI';
requires 'Web::Simple';

feature 'deployment', 'Quick deployment with Server::Starter + FastCGI using bin/service' => sub {
    requires 'Server::Starter';
    requires 'Plack::Handler::FCGI';
    requires 'FCGI';
    requires 'FCGI::ProcManager';
};
