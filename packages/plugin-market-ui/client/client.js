window.__ModuleLoader__.load({ id: "dsh-market-ui", factory: (require) => {


		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
		//#region \0rolldown/runtime.js
		var __create = Object.create;
		var __defProp = Object.defineProperty;
		var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
		var __getOwnPropNames = Object.getOwnPropertyNames;
		var __getProtoOf = Object.getPrototypeOf;
		var __hasOwnProp = Object.prototype.hasOwnProperty;
		var __copyProps = (to, from, except, desc) => {
			if (from && typeof from === "object" || typeof from === "function") for (var keys = __getOwnPropNames(from), i = 0, n = keys.length, key; i < n; i++) {
				key = keys[i];
				if (!__hasOwnProp.call(to, key) && key !== except) __defProp(to, key, {
					get: ((k) => from[k]).bind(null, key),
					enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable
				});
			}
			return to;
		};
		var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(isNodeMode || !mod || !mod.__esModule || !__hasOwnProp.call(mod, "default") ? __defProp(target, "default", {
			value: mod,
			enumerable: true
		}) : target, mod));
		//#endregion
		let react = require("react");
		let _deepseek_ai_dsh_client_ui_primitives = require("@deepseek-ai/dsh-client-ui-primitives");
		_deepseek_ai_dsh_client_ui_primitives = __toESM(_deepseek_ai_dsh_client_ui_primitives, 1);
		let react_jsx_runtime = require("react/jsx-runtime");
		//#region src/client/locales.ts
		/** zh/en dictionaries for the plugin market settings section. */
		const zh = {
			nav: "插件市场",
			subtitle: "搜索并安装社区插件，安装前自动经过安全审查（M2）",
			searchPlaceholder: "输入插件名或关键词，如 dshmarket…",
			search: "搜索",
			searching: "搜索中…",
			installed: "已安装",
			install: "安装",
			installing: "安装中…",
			detail: "详情",
			license: "许可证",
			latest: "最新版本",
			repository: "仓库",
			dependencies: "依赖",
			noResults: "没有找到匹配的插件",
			error: "操作失败",
			confirmInstall: "确定安装「{name}」吗？\n\n安装前会经过 M2 安全审查；含风险项的插件需要逐项确认。",
			needsApproval: "该插件含风险项，需要确认后才能安装：",
			approveAll: "确认并安装",
			rejected: "该插件被安全审查拒绝（RED 项），未安装",
			installedOk: "已安装：{name}",
			close: "关闭",
			emptyInstalled: "尚未安装任何插件"
		};
		const en = {
			nav: "Plugin Market",
			subtitle: "Search and install community plugins (goes through M2 security review before install)",
			searchPlaceholder: "Plugin name or keyword, e.g. dshmarket…",
			search: "Search",
			searching: "Searching…",
			installed: "Installed",
			install: "Install",
			installing: "Installing…",
			detail: "Details",
			license: "License",
			latest: "Latest",
			repository: "Repository",
			dependencies: "Dependencies",
			noResults: "No matching plugins found",
			error: "Failed",
			confirmInstall: "Install \"{name}\"?\n\nIt will go through the M2 security review first; risky items require confirmation.",
			needsApproval: "This plugin has risky items that need your confirmation before install:",
			approveAll: "Confirm and install",
			rejected: "This plugin was rejected by the security review (RED items); not installed",
			installedOk: "Installed: {name}",
			close: "Close",
			emptyInstalled: "No plugins installed yet"
		};
		//#endregion
		//#region \0dsh-css:src/client/MarketSection.module.css.mjs
		const css = "._3gkI7a_root{flex-direction:column;gap:12px;min-width:0;padding:4px 4px 16px;display:flex}._3gkI7a_title{margin:0;font-size:16px;font-weight:500;line-height:24px}._3gkI7a_sub{color:var(--dsw-alias-label-tertiary,#8b93a1);margin:0;font-size:13px;line-height:20px}._3gkI7a_searchRow{align-items:center;gap:8px;display:flex}._3gkI7a_searchInput{border:1px solid var(--dsw-alias-border-l2,#e5e7eb);background:var(--dsw-alias-bg-layer-2,#f7f8fa);min-width:0;height:32px;color:inherit;border-radius:6px;outline:none;flex:1;padding:0 10px;font-size:13px}._3gkI7a_searchInput:focus{border-color:var(--dsw-alias-border-brand,#4f6ef7)}._3gkI7a_actions{align-items:center;gap:8px;display:flex}._3gkI7a_result{background:var(--dsw-alias-bg-layer-2,#f7f8fa);border:1px solid var(--dsw-alias-border-l2,#e5e7eb);border-radius:8px;flex-direction:column;gap:6px;padding:12px 14px;display:flex}._3gkI7a_line{color:var(--dsw-alias-label-secondary,#6b7280);word-break:break-all;font-size:13px;line-height:20px}._3gkI7a_row{justify-content:space-between;align-items:center;gap:8px;display:flex}._3gkI7a_name{font-size:13px;font-weight:500}._3gkI7a_meta{color:var(--dsw-alias-label-tertiary,#9ca3af);font-size:12px}._3gkI7a_desc{color:var(--dsw-alias-label-secondary,#6b7280);margin:0;font-size:12px;line-height:18px}._3gkI7a_ok{color:var(--dsw-alias-state-success-primary,#16a34a);font-size:13px;font-weight:600}._3gkI7a_warn{color:var(--dsw-alias-state-warning-primary,#d97706);font-size:13px;font-weight:600}._3gkI7a_error{color:var(--dsw-alias-state-danger-primary,#dc2626);white-space:pre-wrap;word-break:break-all;font-size:13px}._3gkI7a_hint{color:var(--dsw-alias-label-tertiary,#9ca3af);margin:0;font-size:12px;line-height:18px}";
		const tagId = "\0dsh-css:src//client//MarketSection.module.css.mjs/MarketSection.module.css";
		if (typeof document !== "undefined" && document.querySelector("style[data-plugin-css=" + JSON.stringify(tagId) + "]") === null) {
			const tag = document.createElement("style");
			tag.dataset.plugin = "\0dsh-css:src//client//MarketSection.module.css.mjs";
			tag.dataset.pluginCss = tagId;
			tag.textContent = css;
			document.head.appendChild(tag);
		}
		var MarketSection_module_css_default = {
			"hint": "_3gkI7a_hint",
			"root": "_3gkI7a_root",
			"actions": "_3gkI7a_actions",
			"searchInput": "_3gkI7a_searchInput",
			"sub": "_3gkI7a_sub",
			"name": "_3gkI7a_name",
			"result": "_3gkI7a_result",
			"desc": "_3gkI7a_desc",
			"line": "_3gkI7a_line",
			"warn": "_3gkI7a_warn",
			"searchRow": "_3gkI7a_searchRow",
			"title": "_3gkI7a_title",
			"row": "_3gkI7a_row",
			"error": "_3gkI7a_error",
			"meta": "_3gkI7a_meta",
			"ok": "_3gkI7a_ok"
		};
		//#endregion
		//#region src/client/MarketSection.tsx
		/**
		* Plugin market settings section: search the npm registry through the host
		* loopback routes (/dsh-market/*), show results, and install through the M2
		* security gate. Mirrors the host route response shapes in lib/index.js.
		*/
		function MarketSection(props) {
			const { t } = props;
			const [query, setQuery] = (0, react.useState)("");
			const [searching, setSearching] = (0, react.useState)(false);
			const [results, setResults] = (0, react.useState)(null);
			const [installed, setInstalled] = (0, react.useState)([]);
			const [error, setError] = (0, react.useState)(null);
			const [selected, setSelected] = (0, react.useState)(null);
			const [info, setInfo] = (0, react.useState)(null);
			const [installing, setInstalling] = (0, react.useState)(false);
			const [installMsg, setInstallMsg] = (0, react.useState)(null);
			const [approvalDetail, setApprovalDetail] = (0, react.useState)(null);
			const refreshInstalled = (0, react.useCallback)(async () => {
				try {
					const res = await fetch("/dsh-market/installed");
					const data = await res.json();
					if (res.ok) setInstalled(data.plugins || []);
				} catch {}
			}, []);
			const runSearch = (0, react.useCallback)(async () => {
				const q = query.trim();
				if (!q) return;
				setSearching(true);
				setError(null);
				setResults(null);
				setSelected(null);
				setInfo(null);
				setInstallMsg(null);
				setApprovalDetail(null);
				try {
					const res = await fetch(`/dsh-market/search?q=${encodeURIComponent(q)}`);
					const data = await res.json();
					if (!res.ok) throw new Error(data?.error || data?.detail || `HTTP ${res.status}`);
					setResults(data.packages || []);
				} catch (err) {
					setError(String(err instanceof Error ? err.message : err));
				} finally {
					setSearching(false);
				}
			}, [query]);
			const openInfo = (0, react.useCallback)(async (pkg) => {
				setSelected(pkg);
				setInfo(null);
				setInstallMsg(null);
				setApprovalDetail(null);
				try {
					const res = await fetch(`/dsh-market/info?pkg=${encodeURIComponent(pkg.name)}`);
					const data = await res.json();
					if (!res.ok) throw new Error(data?.error || data?.detail || `HTTP ${res.status}`);
					setInfo(data);
				} catch (err) {
					setError(String(err instanceof Error ? err.message : err));
				}
			}, []);
			const doInstall = (0, react.useCallback)(async (approve = []) => {
				if (!selected) return;
				if (!approve.length && !window.confirm(t("confirmInstall").replace("{name}", selected.name))) return;
				setInstalling(true);
				setInstallMsg(null);
				setApprovalDetail(null);
				try {
					const res = await fetch("/dsh-market/install", {
						method: "POST",
						headers: { "content-type": "application/json" },
						body: JSON.stringify({
							pkg: selected.name,
							approve
						})
					});
					const data = await res.json();
					if (res.status === 409 && data.status === "needs-approval") {
						setApprovalDetail(data.detail || t("needsApproval"));
						return;
					}
					if (!res.ok) {
						if (data.status === "rejected") {
							setInstallMsg(t("rejected"));
							return;
						}
						throw new Error(data?.detail || data?.error || `HTTP ${res.status}`);
					}
					setInstallMsg(t("installedOk").replace("{name}", selected.name));
					await refreshInstalled();
				} catch (err) {
					setError(String(err instanceof Error ? err.message : err));
				} finally {
					setInstalling(false);
				}
			}, [
				selected,
				t,
				refreshInstalled
			]);
			const installedNames = new Set((installed || []).map((p) => p.name));
			return /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
				className: MarketSection_module_css_default.root,
				children: [
					/* @__PURE__ */ (0, react_jsx_runtime.jsx)("h2", {
						className: MarketSection_module_css_default.title,
						children: t("nav")
					}),
					/* @__PURE__ */ (0, react_jsx_runtime.jsx)("p", {
						className: MarketSection_module_css_default.sub,
						children: t("subtitle")
					}),
					/* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
						className: MarketSection_module_css_default.searchRow,
						children: [/* @__PURE__ */ (0, react_jsx_runtime.jsx)("input", {
							className: MarketSection_module_css_default.searchInput,
							value: query,
							placeholder: t("searchPlaceholder"),
							onChange: (event) => setQuery(event.target.value),
							onKeyDown: (event) => {
								if (event.key === "Enter") runSearch();
							}
						}), /* @__PURE__ */ (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.Button, {
							variant: "primary",
							onClick: runSearch,
							disabled: searching,
							icon: searching ? /* @__PURE__ */ (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.IconLoadingOutline16, {}) : /* @__PURE__ */ (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.IconSearch16, {}),
							children: searching ? t("searching") : t("search")
						})]
					}),
					error !== null && /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
						className: MarketSection_module_css_default.error,
						children: [
							t("error"),
							": ",
							error
						]
					}),
					installMsg !== null && /* @__PURE__ */ (0, react_jsx_runtime.jsx)("div", {
						className: MarketSection_module_css_default.ok,
						children: installMsg
					}),
					results !== null && results.length === 0 && /* @__PURE__ */ (0, react_jsx_runtime.jsx)("div", {
						className: MarketSection_module_css_default.warn,
						children: t("noResults")
					}),
					results !== null && results.length > 0 && /* @__PURE__ */ (0, react_jsx_runtime.jsx)("div", {
						className: MarketSection_module_css_default.result,
						children: results.map((pkg) => /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
							className: MarketSection_module_css_default.row,
							children: [/* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", { children: [/* @__PURE__ */ (0, react_jsx_runtime.jsx)("div", {
								className: MarketSection_module_css_default.name,
								children: pkg.name
							}), /* @__PURE__ */ (0, react_jsx_runtime.jsx)("div", {
								className: MarketSection_module_css_default.meta,
								children: pkg.version
							})] }), /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
								className: MarketSection_module_css_default.actions,
								children: [/* @__PURE__ */ (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.Button, {
									onClick: () => openInfo(pkg),
									children: t("detail")
								}), installedNames.has(pkg.name) ? /* @__PURE__ */ (0, react_jsx_runtime.jsx)("span", {
									className: MarketSection_module_css_default.ok,
									children: t("installed")
								}) : /* @__PURE__ */ (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.Button, {
									variant: "primary",
									disabled: installing && selected?.name === pkg.name,
									onClick: () => {
										setSelected(pkg);
										setInfo(null);
										setApprovalDetail(null);
										doInstall([]);
									},
									children: installing && selected?.name === pkg.name ? t("installing") : t("install")
								})]
							})]
						}, pkg.name))
					}),
					selected !== null && /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
						className: MarketSection_module_css_default.result,
						children: [
							/* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
								className: MarketSection_module_css_default.row,
								children: [/* @__PURE__ */ (0, react_jsx_runtime.jsx)("div", {
									className: MarketSection_module_css_default.name,
									children: selected.name
								}), /* @__PURE__ */ (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.Button, {
									onClick: () => {
										setSelected(null);
										setInfo(null);
										setApprovalDetail(null);
									},
									children: t("close")
								})]
							}),
							info !== null && /* @__PURE__ */ (0, react_jsx_runtime.jsxs)(react_jsx_runtime.Fragment, { children: [
								/* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
									className: MarketSection_module_css_default.line,
									children: [
										t("latest"),
										": ",
										/* @__PURE__ */ (0, react_jsx_runtime.jsx)("b", { children: info.latest })
									]
								}),
								info.license && /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
									className: MarketSection_module_css_default.line,
									children: [
										t("license"),
										": ",
										info.license
									]
								}),
								info.description && /* @__PURE__ */ (0, react_jsx_runtime.jsx)("p", {
									className: MarketSection_module_css_default.desc,
									children: info.description
								}),
								info.repository && /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
									className: MarketSection_module_css_default.line,
									children: [
										t("repository"),
										": ",
										info.repository
									]
								}),
								info.dependencies && Object.keys(info.dependencies).length > 0 && /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
									className: MarketSection_module_css_default.line,
									children: [
										t("dependencies"),
										": ",
										Object.entries(info.dependencies).map(([k, v]) => `${k}@${v}`).join(", ")
									]
								})
							] }),
							approvalDetail !== null && /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
								className: MarketSection_module_css_default.warn,
								children: [
									t("needsApproval"),
									/* @__PURE__ */ (0, react_jsx_runtime.jsx)("pre", {
										className: MarketSection_module_css_default.error,
										children: approvalDetail
									}),
									/* @__PURE__ */ (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.Button, {
										variant: "primary",
										disabled: installing,
										onClick: () => doInstall([
											"INSTALL-SCRIPT",
											"NET-EGRESS",
											"CHILD-PROC",
											"SESSION-READ",
											"FILE-WRITE",
											"DEP-VULN"
										]),
										children: installing ? t("installing") : t("approveAll")
									})
								]
							}),
							installing && /* @__PURE__ */ (0, react_jsx_runtime.jsx)("div", {
								className: MarketSection_module_css_default.warn,
								children: t("installing")
							})
						]
					}),
					installed !== null && installed.length > 0 && /* @__PURE__ */ (0, react_jsx_runtime.jsx)("div", {
						className: MarketSection_module_css_default.result,
						children: /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
							className: MarketSection_module_css_default.line,
							children: [
								t("installed"),
								": ",
								installed.map((p) => `${p.name}@${p.version}`).join(", ")
							]
						})
					}),
					installed !== null && installed.length === 0 && /* @__PURE__ */ (0, react_jsx_runtime.jsx)("div", {
						className: MarketSection_module_css_default.hint,
						children: t("emptyInstalled")
					})
				]
			});
		}
		//#endregion
		//#region src/client/index.ts
		/**
		* dsh-market-ui client: registers a "Plugin Market" settings section that
		* drives the host loopback routes (/dsh-market/*). Built by tsdown into the
		* __ModuleLoader__ factory bundle at client/client.js; the only externals are
		* the loader module table's react entries.
		*/
		const NS = "dsh-market-ui";
		/** Primitives this bundle relies on. If the host resolves the primitives
		* module but lacks one, skip registration rather than blank the dialog. */
		const REQUIRED_PRIMITIVES = [
			"Button",
			"IconLoadingOutline16",
			"IconSearch16",
			"IconWarningOutline16"
		];
		function missingPrimitives(mod, required = REQUIRED_PRIMITIVES) {
			return required.filter((name) => mod[name] === void 0);
		}
		const name = "dsh-market-ui";
		const inject = ["slots", "locale"];
		function apply(ctx) {
			const gaps = missingPrimitives(_deepseek_ai_dsh_client_ui_primitives);
			if (gaps.length > 0) {
				console.warn(`[dsh-market-ui] host ui-primitives missing ${gaps.join(", ")} — market section disabled`);
				return;
			}
			ctx.effect(() => ctx.locale.register(NS, {
				zh,
				en
			}), "dsh-market-ui: dictionaries");
			const t = ctx.locale.bind(NS);
			ctx.slots.inject("settings.section", () => ctx.slots.register({
				name: "settings.section",
				id: "dsh-market-ui",
				order: 70,
				label: () => t("nav"),
				locale: NS,
				inject: () => ({ t })
			}, () => (0, react.createElement)(MarketSection, { t })));
		}
		//#endregion
		exports.REQUIRED_PRIMITIVES = REQUIRED_PRIMITIVES;
		exports.apply = apply;
		exports.inject = inject;
		exports.missingPrimitives = missingPrimitives;
		exports.name = name;
		return module.exports;
	}
});

//# sourceMappingURL=client.js.map