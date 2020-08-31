class App extends dn.Process {
	public static var ME : App;
	public static var APP_DIR = "./"; // with leading slash
	public static var RESOURCE_DIR = "bin/"; // with leading slash

	public var jDoc(get,never) : J; inline function get_jDoc() return new J(js.Browser.document);
	public var jBody(get,never) : J; inline function get_jBody() return new J("body");
	public var jPage(get,never) : J; inline function get_jPage() return new J("#page");
	public var jCanvas(get,never) : J; inline function get_jCanvas() return new J("#webgl");

	public var lastKnownMouse : { pageX:Int, pageY:Int };
	var curPageProcess : Null<Page>;
	public var session : SessionData;

	public function new() {
		super();

		ME = this;
		createRoot(Boot.ME.s2d);
		lastKnownMouse = { pageX:0, pageY:0 }
		jCanvas.hide();
		clearMiniNotif();

		// Init window
		#if nwjs
			nw.Window.get().maximize();
			nw.Window.get().on("close", exit.bind(false));
		#elseif electron
			electron.renderer.IpcRenderer.on("winClose", onWindowCloseButton);
		#end

		var win = js.Browser.window;
		win.onblur = onAppBlur;
		win.onfocus = onAppFocus;
		win.onresize = onAppResize;
		win.onmousemove = onAppMouseMove;

		// Init dirs
		var fp = dn.FilePath.fromDir( JsTools.getAppDir() );
		fp.useSlashes();
		APP_DIR = fp.directoryWithSlash;
		RESOURCE_DIR = APP_DIR+"bin/";

		// Restore last stored project state
		session = {
			recentProjects: [],
		}
		session = dn.LocalStorage.readObject("session", session);

		// Auto updater
		var updateVer : Null<String> = null;
		miniNotif("Checking for update...", true);
		electron.renderer.IpcRenderer.invoke("checkUpdate");
		electron.renderer.IpcRenderer.on("updateError", function(ev) {
			miniNotif("Can't check for updates");
		});
		electron.renderer.IpcRenderer.on("updateChecked", function(ev) {
			miniNotif("App is up-to-date");
		});
		electron.renderer.IpcRenderer.on("updateFound", function(ev, version) {
			updateVer = version;
			miniNotif('Downloading $updateVer...');
		});
		electron.renderer.IpcRenderer.on("updateReady", function(ev) {
			miniNotif('Update $updateVer ready!');
			N.appUpdate("Update "+updateVer+" is ready! Click on the INSTALL button above.");
			onUpdateReady(updateVer);
		});

		// Start
		openHome();
	}

	#if electron
	function onWindowCloseButton() {
		exit(false);
	}
	#end

	public function miniNotif(html:String, persist=false) {
		var e = jBody.find("#miniNotif");
		e.empty();

		e.stop(false,true)
			.fadeIn(250)
			.html(html);

		if( !persist )
			e.fadeOut(2500);
	}

	function clearMiniNotif() {
		jBody.find("#miniNotif")
			.stop(false,true)
			.fadeOut(1500);
	}

	function onUpdateReady(ver:String) {
		var e = jBody.find("#updateInstall");
		e.show();
		var bt = e.find("button");
		bt.off().empty();
		bt.append('<strong>Install update</strong>');
		bt.append('<em>Version $ver</em>');
		bt.click(function(_) {
			bt.remove();
			loadPage("updating", { app : Const.APP_NAME });
			jBody.find("*").off();
			delayer.addS(function() {
				electron.renderer.IpcRenderer.invoke("installUpdate");
			}, 1);
		});
	}

	function onAppMouseMove(e:js.html.MouseEvent) {
		lastKnownMouse.pageX = e.pageX;
		lastKnownMouse.pageY = e.pageY;
	}

	function onAppFocus(ev:js.html.Event) {
		if( curPageProcess!=null && !curPageProcess.destroyed )
			curPageProcess.onAppFocus();
	}

	function onAppBlur(ev:js.html.Event) {
		if( curPageProcess!=null && !curPageProcess.destroyed )
			curPageProcess.onAppBlur();
	}

	function onAppResize(ev:js.html.Event) {
		if( curPageProcess!=null && !curPageProcess.destroyed )
			curPageProcess.onAppResize();
	}


	public function saveSessionData() {
		dn.LocalStorage.writeObject("session", session);
	}

	function clearCurPage() {
		jPage.empty();
		if( curPageProcess!=null ) {
			curPageProcess.destroy();
			curPageProcess = null;
		}
	}

	public function registerRecentProject(path:String) {
		session.recentProjects.remove(path);
		session.recentProjects.push(path);
		saveSessionData();
		return true;
	}

	public function unregisterRecentProject(path:String) {
		session.recentProjects.remove(path);
		saveSessionData();
	}

	public function openEditor(project:led.Project, path:String) {
		clearCurPage();
		curPageProcess = new Editor(project, path);
		curPageProcess.onAppResize();
	}

	public function openHome() {
		clearCurPage();
		curPageProcess = new page.Home();
		curPageProcess.onAppResize();
	}

	public function debug(msg:Dynamic, append=false) {
		var wrapper = new J("#debug");
		if( !append )
			wrapper.empty();
		wrapper.show();

		var line = new J("<p/>");
		line.append( Std.string(msg) );
		line.appendTo(wrapper);
	}

	override function onDispose() {
		super.onDispose();
		if( ME==this )
			ME = null;
	}

	public function getDefaultDir() {
		if( session.recentProjects.length==0 )
			return APP_DIR; // TODO find a better default?

		var last = session.recentProjects[session.recentProjects.length-1];
		return dn.FilePath.fromFile(last).directory;
	}

	public function setWindowTitle(?str:String) {
		var base = Const.APP_NAME+" "+Const.getAppVersion();
		if( str==null )
			str = base;
		else
			str = str + "    --    "+base;

		#if nwjs
			nw.Window.get().title = str;
		#elseif electron
			electron.renderer.IpcRenderer.invoke("setWinTitle", str);
		#end
	}

	public function loadPage(id:String, ?vars:Dynamic) {
		ui.modal.Dialog.closeAll();
		ui.Modal.closeAll();
		ui.Tip.clear();
		ui.LastChance.end();

		jCanvas.hide();

		var path = RESOURCE_DIR + 'pages/$id.html';
		var raw = JsTools.readFileString(path);
		if( raw==null )
			throw "Page not found: "+id+" in "+path+"( cwd="+JsTools.getAppDir()+")";

		if( vars!=null ) {
			for(k in Reflect.fields(vars))
				raw = StringTools.replace( raw, '::$k::', Reflect.field(vars,k) );
		}

		jPage
			.off()
			.removeClass()
			.addClass(id)
			.html(raw);

		JsTools.parseComponents(jPage);
	}

	public function exit(force=false) {
		if( !force && Editor.ME!=null && Editor.ME.needSaving ) {
			ui.Modal.closeAll();
			new ui.modal.dialog.UnsavedChanges(Editor.ME.onSave.bind(false), exit.bind(true));
		}
		else {
			#if nwjs
				nw.Window.get().close(true);
			#elseif electron
				electron.renderer.IpcRenderer.invoke("exit");
			#end
		}
	}
}