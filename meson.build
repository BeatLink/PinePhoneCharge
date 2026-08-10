project(
    'chargectl',
    ['c', 'vala'],
    version: '0.1.0',
    license: 'GPL-3.0-or-later',
    meson_version: '>= 0.60.0',
    default_options: ['warning_level=1'],
)

glib = dependency('glib-2.0')
gobject = dependency('gobject-2.0')
gio = dependency('gio-2.0')
json_glib = dependency('json-glib-1.0')
gtk = dependency('gtk+-3.0')
handy = dependency('libhandy-1')

core = files(
    'src/supply.vala',
    'src/settings.vala',
    'src/policy.vala',
    'src/notify.vala',
)

executable(
    'chargectl',
    core + files('src/daemon.vala', 'src/cli.vala'),
    dependencies: [glib, gobject, gio, json_glib],
    install: true,
)

executable(
    'chargectl-gui',
    core + files('src/gui.vala'),
    dependencies: [glib, gobject, gio, json_glib, gtk, handy],
    install: true,
)

policy_test = executable(
    'test-policy',
    files('src/policy.vala', 'tests/policy.vala'),
    dependencies: [glib, gobject],
)
test('policy', policy_test)

install_data(
    'data/io.github.beatlink.Chargectl.desktop',
    install_dir: get_option('datadir') / 'applications',
)
install_data(
    'data/io.github.beatlink.Chargectl.svg',
    install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
)
