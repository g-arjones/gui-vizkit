require 'vizkit'
require 'orocos'
require 'syskit'
require 'roby/interface/async'
require 'vizkit/widgets/config_inspector/config_inspector'

Orocos.load
syskit = Roby::Interface::Async::Interface.new('localhost')
syskit_timer = Qt::Timer.new
syskit_timer.connect(SIGNAL('timeout()')) do
    syskit.poll
end
syskit_timer.start 10

class MainWindow < Qt::MainWindow
    def initialize(syskit)
        super()
        inspector = ConfigInspector.new(syskit)
        setCentralWidget(inspector)
        resize 500, 600
    end
end

window = MainWindow.new(syskit)
window.show
Vizkit.exec
