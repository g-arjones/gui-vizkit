#!/usr/bin/env ruby

module Vizkit
  class UiLoader
    define_widget_for_methods("type",String) do |type|
      type
    end
    define_widget_for_methods("port_type",Orocos::OutputPort,Orocos::Log::OutputPort) do |port|
      port.type_name
    end
    define_widget_for_methods("task_control",Orocos::TaskContext) do |task|
      task.model.name
    end
  end
end

module Vizkit
  Qt::Application.new(ARGV)
  @@auto_reconnect = 2000       #timer interval after which
                                #ports are reconnected if they are no longer alive
  def self.app
    $qApp
  end

  def self.default_loader
    @default_loader
  end

  def self.control value, options=Hash.new,&block
    widget = nil
    case value
    when Orocos::Log::Replay
      widget = @default_loader.log_control
    when Orocos::TaskContext
      widget = @default_loader.widget_for_task_control value
      unless widget
        @task_inspector ||= @default_loader.task_inspector
        widget = @task_inspector
      end
    else
        raise "Cannot handle #{value.class}"
    end
    widget.control value, options
    widget.show
    widget
  end

  def self.display value,options=Hash.new,&block
    #if value is a array
    if value.is_a? Array
      result = Array.new
      value.each do |val|
        result << display(val, options, &block)
      end
      return result
    else 
      #if value is not a array 
      case value
      when Orocos::OutputPort, Orocos::Log::OutputPort
        widget = @default_loader.widget_for(value)
        unless widget 
          @struct_viewer ||= @default_loader.StructViewer
          Vizkit.connect(@struct_viewer) unless @struct_viewer.visible
          widget = @struct_viewer
        end
        #widget.setAttribute(Qt::WA_QuitOnClose, false)
        value.connect_to widget,options ,&block
        widget.show
        return widget
      else
          raise "Cannot handle #{value.class}"
      end
    end
    nil
  end

  def self.connections
    @connections
  end

  def self.exec()
    # the garbage collector has to be called manually for now 
    # because ruby does not now how many objects were created from 
    # the typelib side 
     gc_timer = Qt::Timer.new
     gc_timer.connect(SIGNAL(:timeout)) do 
       GC.start
       auto_reconnect()   #auto reconnect all ports which have set the auto_reconnect flag to true 
     end
     gc_timer.start(@@auto_reconnect)
     $qApp.exec
     gc_timer.stop

  end
  def self.process_events()
    $qApp.processEvents
  end

  def self.load(ui_file,parent = nil)
    @default_loader.load(ui_file,parent)
  end

  def self.disconnect_from(handle)
    case handle
    when Qt::Widget:
      @connections.delete_if do |connection|
        if connection.widget.is_a?(Qt::Object) && handle.findChild(Qt::Widget,connection.widget.objectName)
          connection.disconnect
          true
        else
          if(connection.widget == handle)
            connection.disconnect
            true
          else
            false
          end
        end
      end
    when Orocos::OutputPort:
      @connections.delete_if do |connection|
        if connection.port == handle
          connection.disconnect
          true
        else
          false
        end
      end
    else
      raise "Cannot handle #{handle.class}"
    end
  end

  def self.connect_all()
    @connections.each do |connection|
      connection.connect
    end
  end

  def self.reconnect_all()
    @connections.each do |connection|
      connection.reconnect()
    end
  end

  #reconnects all connection to the widget and its children
  #even if the connection is still alive
  def self.reconnect(widget,force=false)
    if widget.is_a?(Qt::Object)
      @connections.each do |connection|
        if connection.widget.is_a?(Qt::Object) && widget.findChild(Qt::Object,connection.widget.objectName)
          connection.reconnect
        end
      end
    else
      @connections.each do |connection|
          connection.reconnect if connection.widget == widget
      end
    end
  end

  #reconnects all connection which have
  #set the flag auto_reconnect to true 
  def self.auto_reconnect()
    @connections.each do |connection|
      if connection.auto_reconnect && 
         ((connection.widget && connection.respond_to?(:visible) && connection.widget.visible) || !connection.widget) &&  
         !connection.alive?
        puts "Warning lost connection to #{connection.port_full_name}. Trying to reconnect."
        connection.reconnect    
      end
    end
  end

  #connects all connection to the widget and its children
  #if the connection is not responding
  def self.connect(widget)
    if widget.is_a?(Qt::Object)
      @connections.each do |connection|
        if connection.widget.is_a?(Qt::Object) && widget.findChild(Qt::Object,connection.widget.objectName)
          connection.connect
        end
      end
    else
      @connections.each do |connection|
        connection.connect if connection.widget == widget
      end
    end
  end

  #disconnects all connections to widgets 
  def self.disconnect_all
    @connections.each do |connection|
      connection.disconnect
    end
    @connections = Array.new
  end

  # call-seq:
  #   Vizkit.connect_port_to 'corridor_planner', 'plan', widget
  #   Vizkit.connect_port_to 'corridor_planner', 'plan' do |value|
  #     ...
  #   end
  #
  # Asks vizkit to connect the given task,port pair on either a widget, and/or
  # through a block
  #
  # Unlike Orocos::OutputPort#connect_to, this expects a task and port name,
  # i.e. can be called even though the remote task is not started yet
  # 
  # Use the method use_tasks to pre define which tasks shall be used
  # This is use full if tasks are replayed from a logfile 
  def self.connect_port_to(task_name, port_name, widget = nil, options = Hash.new, &block)
    if widget.kind_of?(Hash)
      widget, options = nil, widget
    end

    task = @use_tasks.find{|task| task.name==task_name && task.has_port?(port_name)} if @use_tasks
    if task
      task.port(port_name).connect_to(widget,options,&block)
    else
      #add default option
      options[:auto_reconnect] = true unless options.has_key? :auto_reconnect
      Vizkit.connections << OQConnection.new([task_name, port_name], options, widget, &block)
    end
  end

  # cal-seq:
  #   Vizkit.use_tasks(task1,task2,...)
  #
  # For all connections which will be created via connect_port_to are the tasks
  # used as preferred source. If no suitable task is found connect_port_to will fall
  # back to the corba name server 
  #
  # This is use full if someone wants to use tasks which are replayed
  def self.use_tasks(tasks)
      @use_tasks = Array(tasks).flatten
  end

  class OQConnection < Qt::Object
    #default values
    class << self
      attr_accessor :update_frequency
      attr_accessor :auto_reconnect
    end
    @@update_frequency = 8
    @@auto_reconnect = false

    attr_accessor :auto_reconnect
    attr_reader :update_frequency
    attr_reader :port
    attr_reader :widget
    attr_reader :reader

    def initialize(port,options = Hash.new,widget=nil,&block)
      if widget.is_a? Method
        @callback_fct = widget
        widget = widget.receiver
      end
      if widget.is_a?(Qt::Widget)
        super(widget,&nil)
      else
        super(nil,&nil)
      end

      this_options, @policy = Kernel.filter_options(options,[:update_frequency,:auto_reconnect])
      if port.respond_to?(:to_ary)
        @task_name, @port_name = *port
        @port = nil
      else
        @task_name = port.task.name
        @port_name = port.name
        @port = port
      end
      @widget = widget
      @update_frequency = this_options[:update_frequency] 
      @auto_reconnect = this_options[:auto_reconnect]
      @update_frequency ||= @@update_frequency
      @auto_reconnect ||= @@auto_reconnect
      @block = block
      @reader = nil
      @timer_id = nil
      @last_sample = nil    #save last sample so we can reuse the memory
      @sample_class = nil

      discover_callback_fct
      self
    end

    attr_reader :task_name
    attr_reader :port_name
    def port_full_name
      "#{@task_name}.#{@port_name}"
    end

    def discover_callback_fct
      if @widget && @port 
        #try to find callback_fct for port this is not working if no port is given
        if !@callback_fct && @widget.respond_to?(:loader)
          @callback_fct = @widget.loader.callback_fct @widget.class_name,@port.type_name
        end

        #use default callback_fct
        @callback_fct ||= :update if @widget.respond_to?(:update)
        @callback_fct = @widget.method(@callback_fct) if @callback_fct.is_a? Symbol
        raise "Widget #{@widget.objectName}(#{@widget.class_name}) has no callback function "if !@callback_fct
      else
        @callback_fct = nil
      end
    end

    def update_frequency=(value)
      @update_frequency = value 
      if @timer_id
        killTimer @timer_id
        @timer_id = startTimer(1000/@update_frequency)
      end
    end

    def timerEvent(event)
      #call disconnect if widget is no longer visible
      #this could lead to some problems if the widget wants to
      #log the data 
      #
      if @widget && @widget.is_a?(Qt::Widget) && !@widget.visible
        disconnect
        return
      end

      while(@reader.read_new(@last_sample))
        if @block
          @last_sample = @block.call(@last_sample,port_full_name)
          unless @last_sample.is_a? @sample_class
            raise "#{port_full_name}.connect_to: Code block returned #{@last_sample.class} but #{@sample_class}} was expected!!!"
          end
        end
        @callback_fct.call @last_sample,port_full_name if @callback_fct
      end
    rescue Exception => e
      puts "could not read on #{reader}: #{e.message}"
      disconnect
    end

    def disconnect()
      if @timer_id
        killTimer(@timer_id)
        @timer_id = nil
        # @reader.disconnect this leads to some problems with the timerEvent: reason unknown
        @widget.disconnected(port_full_name) if @widget.respond_to?:disconnected
      end
    end

    def reconnect()
      if Orocos::TaskContext.reachable?(@task_name)
        port = Orocos::TaskContext.get(@task_name).port(@port_name)
        @port = port if port
        discover_callback_fct
        @reader = @port.reader @policy
        if @reader
          @last_sample = @reader.new_sample
          @sample_class = @last_sample.class
          @timer_id = startTimer(1000/@update_frequency) if !@timer_id
          return true
        end
      end
      false
    rescue Exception => e
      STDERR.puts "failed to reconnect: #{e.message}"
      false
    end

    #shadows the connect methods from base object
    #we should use an other name 
    def connect()
      reconnect if !connected?
    end

    def alive?
      return @timer_id && @port.task.reachable?
    end

    alias :connected? :alive?
  end

  class OQLogConnection < OQConnection
    def reconnect()
      @reader =@port.reader @policy
      if @reader
        @timer_id = startTimer(1000/@update_frequency) if !@timer_id
        return true
      end
      false
    end

    def timerEvent(event)
      disconnect if @widget && @widget.is_a?(Qt::Widget) && !@widget.visible
      while(sample = reader.read_new)
        sample = @block.call(sample,port_full_name) if @block
        @callback_fct.call sample,port_full_name if @callback_fct && sample
        @last_sample = sample
      end
    end

    def disconnect()
      if @timer_id
        killTimer(@timer_id)
        @widget.disconnected(port_full_name) if @widget.respond_to?:disconnected
        @timer_id = nil
      end
    end

    def alive?
      return (nil != @timer_id)
    end

    alias :connected? :alive?
  end

  @connections = Array.new
  @default_loader = UiLoader.new
end


