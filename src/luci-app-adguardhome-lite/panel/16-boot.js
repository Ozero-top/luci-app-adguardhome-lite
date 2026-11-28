	function init() {
		initTheme();
		initThemeSync();
		initHeroCore();
		initEvents();
		updateSwitchStates();
		var hash = (window.location.hash || '#overview').replace('#', '');
		if (!hash) hash = 'overview';
		switchTab(hash, false);
		refreshStatus();
		resumePluginUpdate();
		loadLegacyScan();
		setInterval(function () {
			if (document.hidden || state.busy) return;
			refreshStatus(true);
		}, 10000);
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', init);
	} else {
		init();
	}
})();
