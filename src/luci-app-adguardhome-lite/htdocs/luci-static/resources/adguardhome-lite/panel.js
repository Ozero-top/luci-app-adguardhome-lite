/*
 * AdGuard Home 助手 - 独立管理页面
 * 不依赖 LuCI 主题、luci.js 或 XHR，全部使用原生 fetch。
 */
(function () {
	'use strict';

	var CFG = window.AGH || {};
	var U = CFG.urls || {};
	var TOKEN = CFG.token || '';

	var state = {
		status: null,
		settings: null,
		yamlLoaded: false,
		busy: false,
		passShown: false,
		openclash: false,
		updateTimer: null,
		actionTimer: null,
		logTimer: null,
		toastTimer: null
	};

	function $(id) {
		return document.getElementById(id);
	}

	function esc(value) {
		return String(value == null ? '' : value)
			.replace(/&/g, '&amp;')
			.replace(/</g, '&lt;')
			.replace(/>/g, '&gt;')
			.replace(/"/g, '&quot;')
			.replace(/'/g, '&#39;');
	}

	function showToast(text, kind) {
		var el = document.querySelector('.agh-toast');
		if (!el) {
			el = document.createElement('div');
			el.className = 'agh-toast';
			document.body.appendChild(el);
		}
		el.textContent = text;
		el.className = 'agh-toast is-visible' + (kind ? ' is-' + kind : '');
		if (state.toastTimer) clearTimeout(state.toastTimer);
		state.toastTimer = setTimeout(function () {
			el.className = 'agh-toast';
		}, 4500);
	}

	function setMsg(el, text, kind) {
		if (!el) return;
		el.textContent = text || '';
		el.style.whiteSpace = 'pre-wrap';
		el.style.color = kind === 'bad'
			? 'var(--agh-danger)'
			: kind === 'ok'
				? 'var(--agh-success)'
				: 'var(--agh-muted)';
	}

	function isLoginError(err) {
		return err && err.login === true;
	}

	function handleApiError(err, target) {
		if (isLoginError(err)) {
			var text = '登录已过期，请重新登录 LuCI 后刷新本页面。';
			if (target) setMsg(target, text, 'bad');
			showToast(text, 'bad');
			return;
		}
		var msg = err && err.message ? err.message : String(err);
		if (target) setMsg(target, msg, 'bad');
		showToast(msg, 'bad');
	}

	async function parseJsonResponse(r) {
		var ct = r.headers.get('content-type') || '';
		if (ct.indexOf('text/html') >= 0) {
			throw Object.assign(new Error('登录已过期'), { login: true });
		}
		var text = await r.text();
		if (!r.ok) {
			if (text.trim().indexOf('<') === 0) throw Object.assign(new Error('登录已过期'), { login: true });
			throw new Error(text || ('HTTP ' + r.status));
		}
		try {
			return JSON.parse(text);
		} catch (e) {
			if (text.trim().indexOf('<') === 0) throw Object.assign(new Error('登录已过期'), { login: true });
			throw new Error('接口返回格式错误');
		}
	}

	async function apiGet(url) {
		var r = await fetch(url, {
			credentials: 'same-origin',
			cache: 'no-store',
			headers: { 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest' }
		});
		return parseJsonResponse(r);
	}

	async function apiPost(url, data) {
		var body = new URLSearchParams(data || {});
		body.set('token', TOKEN);
		var r = await fetch(url, {
			method: 'POST',
			credentials: 'same-origin',
			cache: 'no-store',
			headers: {
				'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
				'Accept': 'application/json',
				'X-Requested-With': 'XMLHttpRequest'
			},
			body: body.toString()
		});
		var json = await parseJsonResponse(r);
		if (json && json.ok === false) {
			throw new Error(json.error || '操作失败');
		}
		return json;
	}

	async function apiText(url) {
		var r = await fetch(url, {
			credentials: 'same-origin',
			cache: 'no-store',
			headers: { 'Accept': 'text/plain', 'X-Requested-With': 'XMLHttpRequest' }
		});
		var ct = r.headers.get('content-type') || '';
		if (ct.indexOf('text/html') >= 0) {
			throw Object.assign(new Error('登录已过期'), { login: true });
		}
		if (!r.ok) throw new Error('HTTP ' + r.status);
		return await r.text();
	}

	function panelUrl(port) {
		var host = window.location.hostname;
		if (host.indexOf(':') >= 0 && host.charAt(0) !== '[') host = '[' + host + ']';
		return 'http://' + host + ':' + (port || 13800) + '/';
	}

	function modeLabel(mode) {
		if (mode === 'takeover') return '接管 53 端口';
		if (mode === 'openclash') return 'OpenClash 串联（已下线）';
		if (mode === 'clashfirst') return 'OpenClash 前置（Clash → AGH → 真实 DNS）';
		if (mode === 'none') return '仅面板（不接管 DNS）';
		return 'DNSMasq 上游';
	}

	function modeChain(d) {
		var cdp = d.clash_dns_port || '7874';
		if (d.dns_mode === 'takeover') return '客户端 → 53 AdGuard Home → 1745 DNSMasq → Clash / WAN DNS';
		if (d.dns_mode === 'openclash') return '客户端 → 53 DNSMasq → 5333 AdGuard Home → ' + cdp + ' Clash DNS';
		if (d.dns_mode === 'clashfirst') return '客户端 → OpenClash 劫持 → ' + cdp + ' Clash DNS → 5335 AdGuard Home → 真实 DNS';
		if (d.dns_mode === 'none') return '不接管 DNS，仅保留管理面板';
		return '客户端 → 53 DNSMasq → 5333 AdGuard Home → 自动选择上游';
	}

	function channelLabel(channel) {
		return channel === 'beta' ? '测试版' : '稳定版';
	}

	function proxyLabel(proxy) {
		return (!proxy || proxy === 'none') ? '关闭（不使用）' : proxy;
	}

	function setBusy(value) {
		state.busy = value;
		updateSteps(state.status);
	}

	function updatePluginVersion(d) {
		var ver = $('agh-plugin-version');
		var tip = $('agh-plugin-update');
		var p = d && d.plugin;
		if (ver) ver.textContent = (p && p.current) ? 'v' + p.current : '未知';
		if (!tip) return;

		if (p && p.update && p.latest) {
			tip.href = p.url || '#';
			tip.textContent = '发现新版本 v' + p.latest + '，前往更新';
			tip.hidden = false;
		} else {
			tip.hidden = true;
		}
	}

	function updateHeaderStatus() {
		var el = $('agh-header-status');
		if (!el) return;
		var d = state.status;
		if (!d) {
			el.className = 'agh-pill';
			el.textContent = '读取中';
			return;
		}
		if (d.update_running) {
			el.className = 'agh-pill agh-pill-warn';
			el.textContent = '内核安装中';
			return;
		}
		if (d.running) {
			el.className = 'agh-pill agh-pill-ok';
			el.textContent = '运行中';
			return;
		}
		if (d.enabled) {
			el.className = 'agh-pill agh-pill-warn';
			el.textContent = '已启用 / 未运行';
			return;
		}
		el.className = 'agh-pill agh-pill-bad';
		el.textContent = '已停止';
	}

	function attachPasswordActions(pass) {
		var toggle = $('agh-pass-toggle');
		var copy = $('agh-pass-copy');
		if (toggle) {
			toggle.onclick = function () {
				state.passShown = !state.passShown;
				renderStatus();
			};
		}
		if (copy) {
			copy.onclick = function () {
				copyText(pass);
			};
		}
	}

	function renderStatus() {
		var d = state.status;
		updateHeaderStatus();
		updatePluginVersion(d);
		if (!d) {
			var grid = $('agh-status-grid');
			if (grid) grid.innerHTML = '<div class="agh-empty">无法读取状态</div>';
			return;
		}

		var panel = panelUrl(d.web_port);
		var pass = d.admin_pass || '';
		var passHtml = pass
			? '<span class="agh-pass-wrap"><span id="agh-pass-text">' + (state.passShown ? esc(pass) : '••••••••') + '</span>' +
				'<button type="button" class="agh-mini-btn" id="agh-pass-toggle">' + (state.passShown ? '隐藏' : '显示') + '</button>' +
				'<button type="button" class="agh-mini-btn" id="agh-pass-copy">复制</button></span>'
			: '<span class="agh-warn">未设置</span>';

		var rows = [
			['服务状态', d.running ? '<span class="agh-ok">运行中</span>' : '<span class="agh-bad">已停止</span>'],
			['内核版本', d.core ? '<span class="agh-ok">' + esc(d.version || '已安装') + '</span>' : '<span class="agh-bad">未安装</span>'],
			['DNS 接管', esc(modeLabel(d.dns_mode)) + ((d.mode_applied && d.mode_applied !== d.dns_mode) ? ' <span class="agh-warn">（待应用）</span>' : '')],
			['当前链路', '<span class="agh-path">' + esc(modeChain(d)) + '</span>'],
			['更新通道', esc(channelLabel(d.channel))],
			['GitHub 反代', d.channel === 'beta' ? '<span class="agh-hint">测试版不使用</span>' : esc(proxyLabel(d.github_proxy))],
			['面板地址', '<a href="' + esc(panel) + '" target="_blank" rel="noopener">' + esc(panel.replace(/^http:\/\//, '')) + '</a>'],
			['管理员', esc(d.admin_user || 'admin')],
			['面板密码', passHtml],
			['配置文件', d.config_exists ? '<span class="agh-ok">已生成</span>' : '<span class="agh-warn">未生成</span>'],
			['工作目录', '<span class="agh-path">' + esc(d.workdir || '') + '</span>']
		];

		if (d.dns_mode === 'takeover' && d.openclash_hijack && !d.dns_redirect) {
			rows.push(['配置建议', '<span class="agh-warn">检测到 OpenClash DNS 劫持，但把查询收回 53 的规则没有生效，查询可能绕过 AdGuard Home。请在「基础设置」重新保存一次「接管 53 端口」，或检查防火墙状态。</span>']);
		}
		if (d.dns_mode === 'openclash' && d.openclash_hijack_port &&
			d.openclash_hijack_port !== '53' && d.openclash_hijack_port !== String(d.dns_port)) {
			rows.push(['配置建议', '<span class="agh-warn">OpenClash 把 53 直接劫持到 ' + esc(d.openclash_hijack_port) +
				'，查询不经过 DNSMasq，AdGuard Home 被绕过。请改用「OpenClash 前置」。</span>']);
		}
		if (d.dns_mode === 'openclash' && !d.openclash_running) {
			rows.push(['配置建议', '<span class="agh-warn">Clash 内核未运行，AdGuard Home 的上游 ' + esc(d.clash_dns_port || '7874') + ' 不可用，DNS 会解析失败。</span>']);
		}
		if (d.dns_mode === 'clashfirst') {
			if (!d.openclash_running) {
				rows.push(['配置建议', '<span class="agh-warn">Clash 内核未运行，前置链路无法生效。</span>']);
			} else if (!d.openclash_redirect || d.openclash_redirect === '0') {
				rows.push(['配置建议', '<span class="agh-warn">OpenClash 的 DNS 劫持未开启，客户端查询会绕过 AdGuard Home。</span>']);
			} else if (!d.openclash_upstream_agh) {
				rows.push(['配置建议', '<span class="agh-warn">未检测到指向 127.0.0.1:' + String(d.dns_port) + ' 的 OpenClash 上游，可保存一次设置或重启 OpenClash 使其生效。</span>']);
			}
		}

		var html = '';
		for (var i = 0; i < rows.length; i++) {
			html += '<div class="agh-status-item"><span class="agh-k">' + esc(rows[i][0]) + '</span><span class="agh-v">' + rows[i][1] + '</span></div>';
		}
		var grid = $('agh-status-grid');
		if (grid) grid.innerHTML = html;

		attachPasswordActions(pass);
		updateSteps(d);

		if (d.update_running && !state.updateTimer) {
			showProgress();
			startProgressPoll();
		}
	}

	function updateSteps(d) {
		if (!d) return;
		var busy = state.busy || d.action_running || d.update_running;

		var installBtn = $('agh-install-btn');
		var enableBtn = $('agh-enable-btn');
		var panelLink = $('agh-panel-link');

		if (installBtn) {
			installBtn.disabled = busy;
			installBtn.textContent = d.core ? '重新安装/更新内核' : '安装内核';
		}
		var coreHint = $('agh-core-hint');
		if (coreHint) {
			coreHint.textContent = d.core
				? '已安装，当前版本：' + (d.version || '未知')
				: (d.update_running ? '正在安装...' : '尚未安装内核');
		}

		if (enableBtn) {
			enableBtn.disabled = !d.core || busy;
			enableBtn.textContent = d.running ? '重新应用设置' : '一键启用';
		}
		var enableHint = $('agh-enable-hint');
		if (enableHint) {
			if (!d.core) enableHint.textContent = '请先完成第 1 步。';
			else if (d.running) enableHint.textContent = '服务正在运行。';
			else if (d.enabled) enableHint.textContent = '已启用但当前未运行，请点击启动或查看日志。';
			else enableHint.textContent = '内核已就绪，可以启用。';
		}

		if (panelLink) {
			if (d.running) {
				panelLink.href = panelUrl(d.web_port);
				panelLink.className = 'agh-btn agh-btn-secondary';
				panelLink.textContent = '打开控制台';
				panelLink.removeAttribute('aria-disabled');
			} else {
				panelLink.href = '#';
				panelLink.className = 'agh-btn agh-btn-secondary is-disabled';
				panelLink.textContent = '服务未运行';
				panelLink.setAttribute('aria-disabled', 'true');
			}
		}
		var consoleHint = $('agh-console-hint');
		if (consoleHint) {
			consoleHint.textContent = d.running
				? '面板地址：' + panelUrl(d.web_port)
				: '启用服务后即可打开面板。';
		}

		var headerConsole = $('agh-header-console');
		if (headerConsole) {
			if (d.running) {
				headerConsole.href = panelUrl(d.web_port);
				headerConsole.className = 'agh-badge agh-badge-link';
				headerConsole.removeAttribute('aria-disabled');
			} else {
				headerConsole.href = '#';
				headerConsole.className = 'agh-badge agh-badge-link is-disabled';
				headerConsole.setAttribute('aria-disabled', 'true');
			}
		}

		var startBtn = $('agh-start-btn');
		var stopBtn = $('agh-stop-btn');
		var restartBtn = $('agh-restart-btn');
		if (startBtn) startBtn.disabled = busy || d.running;
		if (stopBtn) stopBtn.disabled = busy || (!d.running && !d.enabled);
		if (restartBtn) restartBtn.disabled = busy || !d.core;
	}

	function fmtCount(value) {
		if (value === null || value === undefined || value === '' || isNaN(Number(value))) return '-';
		return Number(value).toLocaleString('zh-CN');
	}

	// 统计随 /status 一起返回，这里只负责渲染，避免额外请求
	function renderStats(d) {
		var hint = $('agh-stats-hint');
		var keys = {
			queries: 'agh-stat-queries',
			blocked: 'agh-stat-blocked',
			malware: 'agh-stat-malware',
			adult: 'agh-stat-adult'
		};
		if (!d || d.ok === false) {
			Object.keys(keys).forEach(function (k) {
				var el = $(keys[k]);
				if (el) el.textContent = '-';
			});
			if (hint) hint.textContent = (d && d.error) ? d.error : '统计读取失败。';
			return;
		}
		Object.keys(keys).forEach(function (k) {
			if (k === 'adult') return;
			var el = $(keys[k]);
			if (el) el.textContent = fmtCount(d[k]);
		});
		var adultEl = $('agh-stat-adult');
		if (adultEl) {
			adultEl.textContent = (d.adult_filter && !Number(d.adult)) ? '已启用' : fmtCount(d.adult);
		}
		var updated = $('agh-stats-updated');
		if (updated) {
			updated.textContent = '更新于 ' + new Date().toLocaleTimeString('zh-CN', { hour12: false });
		}
		if (hint) {
			var tips = [];
			if (d.protection === false) tips.push('防护已关闭');
			if (d.safebrowsing === false) tips.push('未开启安全浏览，「恶意/钓鱼」会一直是 0（它依赖境外在线服务，开启后若解析变慢请关闭）');
			if (d.adult_filter) {
				tips.push('成人规则已启用，命中数计入「已拦截」');
			} else if (d.parental === false) {
				tips.push('未开启成人内容拦截，「成人内容」会一直是 0');
			}
			hint.textContent = tips.length
				? tips.join('；') + '，可到 AdGuard Home 面板开启。'
				: '数据来自 AdGuard Home 统计接口，每 10 秒随状态自动刷新。';
		}
	}

	async function refreshStatus(silent) {
		try {
			var d = await apiGet(U.status);
			state.status = d;
			renderStatus();
			if (d && d.stats) renderStats(d.stats);
			if (d.action_running && !state.busy) {
				state.busy = true;
				pollAction(null);
			}
		} catch (err) {
			if (!silent) handleApiError(err);
		}
	}

	function pollAction(onDone) {
		if (state.actionTimer) clearTimeout(state.actionTimer);
		var ticks = 0;
		state.busy = true;
		updateSteps(state.status);

		async function tick() {
			ticks++;
			try {
				var d = await apiGet(U.status);
				state.status = d;
				renderStatus();
				if (d && !d.action_running) {
					state.busy = false;
					updateSteps(d);
					if (onDone) onDone(d);
					showToast('操作完成', 'ok');
					return;
				}
			} catch (err) {
				handleApiError(err);
			}
			if (ticks < 30) {
				state.actionTimer = setTimeout(tick, 1500);
			} else {
				state.busy = false;
				updateSteps(state.status);
				showToast('操作仍在后台执行，请稍后刷新页面', 'warn');
			}
		}
		tick();
	}

	function postService(action, confirmText) {
		if (confirmText && !window.confirm(confirmText)) return;
		state.busy = true;
		updateSteps(state.status);
		apiPost(U.service, { action: action }).then(function () {
			showToast('正在执行，请稍候...', 'ok');
			pollAction();
		}).catch(function (err) {
			state.busy = false;
			updateSteps(state.status);
			handleApiError(err);
		});
	}

	function showProgress(text) {
		var wrap = $('agh-progress-wrap');
		if (wrap) wrap.hidden = false;
		var log = $('agh-progress-log');
		if (log && text) log.textContent = text;
		var stateEl = $('agh-progress-state');
		if (stateEl) stateEl.textContent = '';
	}

	function hideProgress() {
		var wrap = $('agh-progress-wrap');
		if (wrap) wrap.hidden = true;
	}

	function startProgressPoll() {
		if (state.updateTimer) return;
		var ticks = 0;
		state.updateTimer = true;
		state.busy = true;

		async function tick() {
			ticks++;
			try {
				var d = await apiGet(U.coreProgress);
				var log = $('agh-progress-log');
				if (log && d && d.log) {
					log.textContent = d.log;
					log.scrollTop = log.scrollHeight;
				}
				var stateEl = $('agh-progress-state');
				if (d && d.running) {
					if (stateEl) stateEl.textContent = '进行中...';
					ticks = 0;
					state.updateTimer = setTimeout(tick, 2000);
					return;
				}
				if (d && typeof d.code === 'number') {
					state.updateTimer = null;
					state.busy = false;
					if (stateEl) stateEl.textContent = d.code === 0 ? '完成' : ('失败（错误码 ' + d.code + '）');
					refreshStatus(true);
					showToast(d.code === 0 ? '内核安装/更新完成' : '安装失败，请查看日志', d.code === 0 ? 'ok' : 'bad');
					if (d.code === 0) setTimeout(hideProgress, 3000);
					return;
				}
				if (ticks < 8) {
					if (stateEl) stateEl.textContent = '等待任务启动...';
					state.updateTimer = setTimeout(tick, 1500);
				} else {
					state.updateTimer = null;
					state.busy = false;
					if (stateEl) stateEl.textContent = '未检测到任务';
					showToast('未能启动安装任务，请查看运行日志', 'bad');
				}
			} catch (err) {
				state.updateTimer = null;
				state.busy = false;
				handleApiError(err);
			}
		}
		tick();
	}

	function installCore() {
		if (!window.confirm('将从 AdGuard 官方源或 GitHub 反代下载最新内核，可能需要几分钟。确定继续？')) return;
		showProgress('正在启动安装任务...');
		state.busy = true;
		updateSteps(state.status);
		apiPost(U.coreInstall, {}).then(function () {
			startProgressPoll();
		}).catch(function (err) {
			state.busy = false;
			updateSteps(state.status);
			handleApiError(err);
		});
	}

	function setSelectValue(id, value) {
		var el = $(id);
		if (!el) return;
		var found = false;
		for (var i = 0; i < el.options.length; i++) {
			if (el.options[i].value === value) {
				el.value = value;
				found = true;
				break;
			}
		}
		if (!found && value) {
			var opt = document.createElement('option');
			opt.value = value;
			opt.textContent = value;
			el.appendChild(opt);
			el.value = value;
		}
	}

	function pickedBypassIfaces() {
		var menu = $('agh-bypass-iface-menu');
		if (!menu) return '';
		return Array.prototype.slice.call(menu.querySelectorAll('input:checked'))
			.map(function (el) { return el.value; })
			.join(' ');
	}

	function updateBypassIfaceLabel() {
		var label = $('agh-bypass-iface-label');
		if (!label) return;
		var picked = pickedBypassIfaces().split(/\s+/).filter(Boolean);
		label.textContent = picked.length ? ('已排除：' + picked.join('、')) : '全部接管';
		label.title = picked.join(' ');
	}

	function renderBypassIfaces(devices, configured) {
		var menu = $('agh-bypass-iface-menu');
		if (!menu) return;
		var picked = (configured || '').split(/\s+/);
		var list = (devices || []).slice();
		picked.forEach(function (name) {
			if (name && list.indexOf(name) < 0) list.push(name);
		});
		menu.innerHTML = '';
		if (!list.length) {
			menu.textContent = '未检测到可用接口';
			updateBypassIfaceLabel();
			return;
		}
		list.sort();
		list.forEach(function (name) {
			var item = document.createElement('label');
			item.className = 'agh-option';
			var input = document.createElement('input');
			input.type = 'checkbox';
			input.value = name;
			input.checked = picked.indexOf(name) >= 0;
			input.addEventListener('change', updateBypassIfaceLabel);
			var text = document.createElement('span');
			text.textContent = name;
			item.appendChild(input);
			item.appendChild(text);
			menu.appendChild(item);
		});
		updateBypassIfaceLabel();
	}

	function applyModeLocks(mode) {
		var takeover = mode === 'takeover';
		var group = $('agh-bypass-group');
		if (group) {
			group.classList.toggle('is-locked', !takeover);
			Array.prototype.slice.call(group.querySelectorAll('input, button, select')).forEach(function (el) {
				el.disabled = !takeover;
			});
			if (!takeover) {
				var menu = $('agh-bypass-iface-menu');
				if (menu) menu.hidden = true;
			}
		}
		var note = $('agh-bypass-note');
		if (note) note.style.display = takeover ? 'none' : '';

		var clashOption = document.querySelector('#agh-set-dns-mode option[value="clashfirst"]');
		if (clashOption) {
			clashOption.disabled = !state.openclash;
			clashOption.textContent = state.openclash
				? 'OpenClash 前置（Clash 7874 → AGH 5335 → 真实 DNS）'
				: 'OpenClash 前置（未安装 OpenClash，不可用）';
		}

		var modeNote = $('agh-dns-mode-note');
		if (modeNote) {
			var text = '';
			if (state.openclash && mode === 'upstream') {
				text = '检测到 OpenClash：该模式会改写 DNSMasq 上游，重启 OpenClash 后可能被覆盖，建议改用「接管 53 端口」。';
			} else if (!state.openclash && mode === 'clashfirst') {
				text = 'OpenClash 未安装，「OpenClash 前置」模式不会生效，请改用「接管 53 端口」。';
			}
			modeNote.textContent = text;
			modeNote.style.display = text ? '' : 'none';
		}
	}

	async function loadSettings() {
		var msgEl = $('agh-settings-msg');
		try {
			var d = await apiGet(U.settingsGet);
			if (d && d.ok === false) throw new Error(d.error || '读取设置失败');
			state.settings = d;
			var enabled = $('agh-set-enabled');
			if (enabled) enabled.checked = !!d.enabled;
			setSelectValue('agh-set-dns-mode', d.dns_mode);
			var port = $('agh-set-webport');
			if (port) port.value = d.webport;
			setSelectValue('agh-set-binpath', d.binpath);
			setSelectValue('agh-set-workdir', d.workdir);
			setSelectValue('agh-set-channel', d.channel);
			setSelectValue('agh-set-github-proxy', d.github_proxy);
			var adult = $('agh-set-adult');
			if (adult) adult.checked = !!d.adult_block;
			renderBypassIfaces(d.devices, d.bypass_ifaces);
			var bypassClients = $('agh-set-bypass-clients');
			if (bypassClients) bypassClients.value = d.bypass_clients || '';
			state.openclash = !!d.openclash_installed;
			applyModeLocks(d.dns_mode);
			var path = $('agh-yaml-path');
			if (path && d.config_path) path.textContent = d.config_path;
			setMsg(msgEl, '', '');
		} catch (err) {
			handleApiError(err, msgEl);
		}
	}

	async function saveSettings(event) {
		event.preventDefault();
		var msgEl = $('agh-settings-msg');
		var btn = $('agh-save-settings-btn');
		var port = $('agh-set-webport');
		var portValue = port ? port.value.trim() : '';
		var n = Number(portValue);

		if (!portValue || !Number.isInteger(n) || n < 1 || n > 65535) {
			setMsg(msgEl, '管理面板端口必须是 1-65535 之间的整数。', 'bad');
			return;
		}
		if (n === 53 || n === 1745 || n === 5333 || n === 5335) {
			setMsg(msgEl, '管理面板端口不能使用 53、1745、5333 或 5335。', 'bad');
			return;
		}

		var data = {
			enabled: $('agh-set-enabled').checked ? '1' : '0',
			dns_mode: $('agh-set-dns-mode').value,
			webport: String(n),
			binpath: $('agh-set-binpath').value,
			workdir: $('agh-set-workdir').value,
			channel: $('agh-set-channel').value,
			github_proxy: $('agh-set-github-proxy').value,
			adult_block: ($('agh-set-adult') && $('agh-set-adult').checked) ? '1' : '0',
			bypass_ifaces: pickedBypassIfaces(),
			bypass_clients: $('agh-set-bypass-clients') ? $('agh-set-bypass-clients').value.trim() : ''
		};

		if (btn) btn.disabled = true;
		setMsg(msgEl, '正在保存并应用设置...', '');
		try {
			await apiPost(U.settingsSave, data);
			setMsg(msgEl, '设置已保存，正在应用...', 'ok');
			showToast('设置已保存，正在重启服务...', 'ok');
			pollAction(function () {
				if (btn) btn.disabled = false;
				loadSettings();
				refreshStatus(true);
			});
		} catch (err) {
			if (btn) btn.disabled = false;
			handleApiError(err, msgEl);
		}
	}

	async function loadYaml() {
		var msgEl = $('agh-yaml-msg');
		var editor = $('agh-yaml-editor');
		if (!editor) return;
		try {
			var d = await apiGet(U.yamlGet);
			editor.value = d.yaml || '';
			updateYamlCount();
			var path = $('agh-yaml-path');
			if (path && d.path) path.textContent = d.path;
			state.yamlLoaded = true;
			setMsg(msgEl, d.yaml ? '' : '配置文件尚未生成，请先启用服务。', d.yaml ? '' : 'bad');
		} catch (err) {
			handleApiError(err, msgEl);
		}
	}

	function updateYamlCount() {
		var editor = $('agh-yaml-editor');
		var count = $('agh-yaml-count');
		if (editor && count) count.textContent = editor.value.length + ' 字符';
	}

	async function saveYaml() {
		var editor = $('agh-yaml-editor');
		var msgEl = $('agh-yaml-msg');
		var btn = $('agh-yaml-save');
		if (!editor) return;
		if (!window.confirm('将校验并保存 AdGuardHome.yaml，随后重启服务。确定继续？')) return;
		if (btn) btn.disabled = true;
		setMsg(msgEl, '正在校验配置...', '');
		try {
			await apiPost(U.yamlSave, { yaml: editor.value });
			setMsg(msgEl, '配置已保存，正在重启服务...', 'ok');
			showToast('配置已保存，正在重启服务...', 'ok');
			pollAction(function () {
				if (btn) btn.disabled = false;
				loadYaml();
				refreshStatus(true);
			});
		} catch (err) {
			if (btn) btn.disabled = false;
			handleApiError(err, msgEl);
		}
	}

	async function loadLogs() {
		var box = $('agh-log-box');
		if (!box) return;
		try {
			var text = await apiText(U.logs);
			box.textContent = text || '暂无相关日志。';
			box.scrollTop = box.scrollHeight;
		} catch (err) {
			box.textContent = '读取日志失败：' + (err && err.message ? err.message : err);
			handleApiError(err);
		}
	}

	function downloadLogs() {
		var box = $('agh-log-box');
		if (!box) return;
		var blob = new Blob([box.textContent || ''], { type: 'text/plain;charset=utf-8' });
		var a = document.createElement('a');
		var d = new Date();
		var stamp = d.getFullYear() + ('0' + (d.getMonth() + 1)).slice(-2) + ('0' + d.getDate()).slice(-2)
			+ '-' + ('0' + d.getHours()).slice(-2) + ('0' + d.getMinutes()).slice(-2);
		a.href = URL.createObjectURL(blob);
		a.download = 'adguardhome-lite-log-' + stamp + '.txt';
		a.click();
		URL.revokeObjectURL(a.href);
	}

	function copyText(text) {
		if (!text) return;
		if (navigator.clipboard && window.isSecureContext) {
			navigator.clipboard.writeText(text);
			showToast('密码已复制到剪贴板', 'ok');
			return;
		}
		var ta = document.createElement('textarea');
		ta.value = text;
		ta.style.position = 'fixed';
		ta.style.left = '-9999px';
		document.body.appendChild(ta);
		ta.select();
		try {
			document.execCommand('copy');
			showToast('密码已复制到剪贴板', 'ok');
		} catch (e) {
			showToast('浏览器不支持自动复制，请手动选择密码', 'bad');
		}
		document.body.removeChild(ta);
	}

	async function savePassword(event) {
		event.preventDefault();
		var msgEl = $('agh-pass-msg');
		var btn = $('agh-savepass-btn');
		var pwEl = $('agh-newpass');
		var pw2El = $('agh-newpass2');
		var pw = pwEl ? pwEl.value : '';
		var pw2 = pw2El ? pw2El.value : '';

		if (!pw || pw.length < 8) {
			setMsg(msgEl, '新密码至少需要 8 个字符。', 'bad');
			return;
		}
		if (pw !== pw2) {
			setMsg(msgEl, '两次输入的密码不一致。', 'bad');
			return;
		}
		if (typeof TwinBcrypt === 'undefined') {
			setMsg(msgEl, '密码组件加载失败，请刷新页面后重试。', 'bad');
			return;
		}

		var hash;
		try {
			hash = TwinBcrypt.hashSync(pw, 10);
		} catch (e) {
			setMsg(msgEl, '密码哈希计算失败：' + e, 'bad');
			return;
		}

		if (btn) btn.disabled = true;
		setMsg(msgEl, '正在保存新密码...', '');
		try {
			await apiPost(U.password, { hash: hash, password: pw });
			setMsg(msgEl, '密码已保存，正在重启服务...', 'ok');
			showToast('面板密码修改成功', 'ok');
			if (pwEl) pwEl.value = '';
			if (pw2El) pw2El.value = '';
			pollAction(function () {
				if (btn) btn.disabled = false;
				refreshStatus(true);
			});
		} catch (err) {
			if (btn) btn.disabled = false;
			handleApiError(err, msgEl);
		}
	}

	function switchTab(name, updateHash) {
		var valid = ['overview', 'settings', 'advanced', 'logs', 'guide'];
		if (valid.indexOf(name) < 0) name = 'overview';
		var meta = {
			overview: ['概览', '服务状态与三步配置'],
			settings: ['基础设置', '服务、DNS、内核与面板密码'],
			advanced: ['高级配置', '直接编辑 AdGuardHome.yaml'],
			logs: ['运行日志', '系统与服务日志'],
			guide: ['使用引导', '安装、配置与故障排查']
		};

		var tabs = document.querySelectorAll('.agh-tab');
		for (var i = 0; i < tabs.length; i++) {
			tabs[i].classList.toggle('is-active', tabs[i].getAttribute('data-tab') === name);
		}
		var panels = document.querySelectorAll('.agh-tab-panel');
		for (var j = 0; j < panels.length; j++) {
			panels[j].classList.toggle('is-active', panels[j].id === 'agh-tab-' + name);
		}
		var title = $('agh-page-title');
		var subtitle = $('agh-page-subtitle');
		if (title) title.textContent = meta[name][0];
		if (subtitle) subtitle.textContent = meta[name][1];

		if (name === 'settings' && !state.settings) loadSettings();
		if (name === 'advanced' && !state.yamlLoaded) loadYaml();
		if (name === 'logs') loadLogs();

		if (updateHash !== false && window.history && window.history.replaceState) {
			window.history.replaceState(null, '', '#' + name);
		}
	}

	function initEvents() {
		var tabs = document.querySelectorAll('.agh-tab');
		for (var i = 0; i < tabs.length; i++) {
			tabs[i].onclick = function () {
				switchTab(this.getAttribute('data-tab'));
			};
		}
		var gotoButtons = document.querySelectorAll('[data-goto]');
		for (var j = 0; j < gotoButtons.length; j++) {
			gotoButtons[j].onclick = function () {
				switchTab(this.getAttribute('data-goto'));
			};
		}

		if ($('agh-refresh-status')) $('agh-refresh-status').onclick = function () { refreshStatus(); };
		if ($('agh-install-btn')) $('agh-install-btn').onclick = installCore;
		if ($('agh-enable-btn')) $('agh-enable-btn').onclick = function () {
			postService('bootstrap', '将启动 AdGuard Home 并接管路由器 DNS。确定继续？');
		};
		if ($('agh-start-btn')) $('agh-start-btn').onclick = function () { postService('start'); };
		if ($('agh-stop-btn')) $('agh-stop-btn').onclick = function () {
			postService('stop', '将停止 AdGuard Home 并关闭面板，同时恢复 DNSMasq 原始设置。确定继续？');
		};
		if ($('agh-restart-btn')) $('agh-restart-btn').onclick = function () {
			postService('restart', '将重启 AdGuard Home 服务。确定继续？');
		};

		if ($('agh-settings-form')) $('agh-settings-form').onsubmit = saveSettings;
		if ($('agh-set-dns-mode')) {
			$('agh-set-dns-mode').onchange = function () {
				applyModeLocks(this.value);
			};
		}
		if ($('agh-bypass-iface-toggle')) {
			$('agh-bypass-iface-toggle').onclick = function (e) {
				e.stopPropagation();
				var menu = $('agh-bypass-iface-menu');
				if (menu) menu.hidden = !menu.hidden;
			};
			document.addEventListener('click', function (e) {
				var menu = $('agh-bypass-iface-menu');
				var dd = $('agh-bypass-iface-dd');
				if (menu && !menu.hidden && dd && !dd.contains(e.target)) menu.hidden = true;
			});
		}
		if ($('agh-password-form')) $('agh-password-form').onsubmit = savePassword;
		if ($('agh-yaml-load')) $('agh-yaml-load').onclick = function () {
			if (state.yamlLoaded && !window.confirm('重新加载会丢弃当前未保存的修改。确定继续？')) return;
			loadYaml();
		};
		if ($('agh-yaml-save')) $('agh-yaml-save').onclick = saveYaml;
		if ($('agh-yaml-editor')) $('agh-yaml-editor').oninput = updateYamlCount;

		if ($('agh-log-refresh')) $('agh-log-refresh').onclick = loadLogs;
		if ($('agh-log-download')) $('agh-log-download').onclick = downloadLogs;
		if ($('agh-log-auto')) {
			$('agh-log-auto').onchange = function () {
				if (state.logTimer) {
					clearInterval(state.logTimer);
					state.logTimer = null;
				}
				if (this.checked) {
					state.logTimer = setInterval(function () {
						if ($('agh-tab-logs')) loadLogs();
					}, 5000);
				}
			};
		}

		window.addEventListener('hashchange', function () {
			switchTab((window.location.hash || '#overview').replace('#', ''), false);
		});
	}

	function init() {
		initEvents();
		var hash = (window.location.hash || '#overview').replace('#', '');
		if (!hash) hash = 'overview';
		switchTab(hash, false);
		refreshStatus();
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
