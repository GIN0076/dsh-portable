window.__ModuleLoader__.load({ id: "dsh-update-check", factory: (require) => {


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
		/** zh/en dictionaries for the update-check settings section. */
		const zh = {
			nav: "更新检查",
			subtitle: "一键检查 DSH-Portable 是否有新版本，并可立即更新",
			check: "检查更新",
			checking: "检查中…",
			current: "当前版本",
			latest: "最新版本",
			upToDate: "✓ 已是最新版本",
			updateAvailable: "发现新版本",
			apply: "立即更新",
			applying: "更新已开始…",
			confirmApply: "确定现在更新吗？\n\n更新会先停止当前应用，自动下载并构建新版本（通常需要几分钟到几十分钟），完成后请重新打开软件。",
			applyStarted: "更新已开始。完成前请勿手动操作，完成后重新打开 DSH-Portable 即可使用新版本。",
			applyFailed: "启动更新失败",
			error: "检查失败",
			hint: "也可以右键托盘图标 → 检查更新"
		};
		const en = {
			nav: "Update Check",
			subtitle: "One-click check for a new DSH-Portable version, and update right away",
			check: "Check for updates",
			checking: "Checking…",
			current: "Current version",
			latest: "Latest version",
			upToDate: "✓ You are up to date",
			updateAvailable: "An update is available",
			apply: "Update now",
			applying: "Update started…",
			confirmApply: "Update now?\n\nThe app will be stopped first, then the new version will be downloaded and built (usually a few minutes). Reopen DSH-Portable when it is done.",
			applyStarted: "Update started. Wait for it to finish, then reopen DSH-Portable to use the new version.",
			applyFailed: "Failed to start the update",
			error: "Check failed",
			hint: "You can also right-click the tray icon → Check for updates"
		};
		//#endregion
		//#region \0dsh-css:src/client/UpdateSection.module.css.mjs
		const css = ".b3wc9a_root{flex-direction:column;gap:12px;min-width:0;padding:4px 4px 16px;display:flex}.b3wc9a_title{margin:0;font-size:16px;font-weight:500;line-height:24px}.b3wc9a_sub{color:var(--dsw-alias-label-tertiary,#8b93a1);margin:0;font-size:13px;line-height:20px}.b3wc9a_actions{align-items:center;gap:8px;display:flex}.b3wc9a_result{background:var(--dsw-alias-bg-layer-2,#f7f8fa);border:1px solid var(--dsw-alias-border-l2,#e5e7eb);border-radius:8px;flex-direction:column;gap:6px;padding:12px 14px;display:flex}.b3wc9a_line{color:var(--dsw-alias-label-secondary,#6b7280);font-size:13px;line-height:20px}.b3wc9a_ok{color:var(--dsw-alias-state-success-primary,#16a34a);font-size:13px;font-weight:600}.b3wc9a_warn{color:var(--dsw-alias-state-warning-primary,#d97706);font-size:13px;font-weight:600}.b3wc9a_error{color:var(--dsw-alias-state-danger-primary,#dc2626);white-space:pre-wrap;word-break:break-all;font-size:13px}.b3wc9a_hint{color:var(--dsw-alias-label-tertiary,#9ca3af);margin:0;font-size:12px;line-height:18px}";
		const tagId = "dsh-update-check/UpdateSection.module.css";
		if (typeof document !== "undefined" && document.querySelector("style[data-plugin-css=" + JSON.stringify(tagId) + "]") === null) {
			const tag = document.createElement("style");
			tag.dataset.plugin = "dsh-update-check";
			tag.dataset.pluginCss = tagId;
			tag.textContent = css;
			document.head.appendChild(tag);
		}
		var UpdateSection_module_css_default = {
			"line": "b3wc9a_line",
			"hint": "b3wc9a_hint",
			"title": "b3wc9a_title",
			"error": "b3wc9a_error",
			"warn": "b3wc9a_warn",
			"ok": "b3wc9a_ok",
			"result": "b3wc9a_result",
			"sub": "b3wc9a_sub",
			"actions": "b3wc9a_actions",
			"root": "b3wc9a_root"
		};
		//#endregion
		//#region src/client/UpdateSection.tsx
		/**
		* The update-check settings section: a "check" button that runs the host
		* route /dsh-update/check (packages/update-engine/update-dsh.ps1 check mode),
		* and — when an update is available — an "Update now" button that POSTs to
		* /dsh-update/apply (apply mode, stopped by the updater mid-flight).
		*/
		function UpdateSection(props) {
			const { t } = props;
			const [checking, setChecking] = (0, react.useState)(false);
			const [result, setResult] = (0, react.useState)(null);
			const [error, setError] = (0, react.useState)(null);
			const [applying, setApplying] = (0, react.useState)(false);
			const [applyFailed, setApplyFailed] = (0, react.useState)(null);
			const run = (0, react.useCallback)(async () => {
				setChecking(true);
				setError(null);
				setResult(null);
				try {
					const res = await fetch("/dsh-update/check");
					const data = await res.json();
					if (!res.ok) throw new Error(data?.detail || `HTTP ${res.status}`);
					setResult(data);
				} catch (err) {
					setError(String(err instanceof Error ? err.message : err));
				} finally {
					setChecking(false);
				}
			}, []);
			const apply = (0, react.useCallback)(async () => {
				if (!window.confirm(t("confirmApply"))) return;
				setApplyFailed(null);
				setApplying(true);
				try {
					const res = await fetch("/dsh-update/apply", { method: "POST" });
					const data = await res.json();
					if (!res.ok) throw new Error(data?.error || data?.detail || `HTTP ${res.status}`);
					if (data?.status !== "started") throw new Error(data?.detail || "unexpected response");
				} catch (err) {
					setApplying(false);
					setApplyFailed(t("applyFailed") + ": " + String(err instanceof Error ? err.message : err));
				}
			}, [t]);
			const showApply = result !== null && result.status === "update-available" && !applying;
			return /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
				className: UpdateSection_module_css_default.root,
				children: [
					/* @__PURE__ */ (0, react_jsx_runtime.jsx)("h2", {
						className: UpdateSection_module_css_default.title,
						children: t("nav")
					}),
					/* @__PURE__ */ (0, react_jsx_runtime.jsx)("p", {
						className: UpdateSection_module_css_default.sub,
						children: t("subtitle")
					}),
					/* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
						className: UpdateSection_module_css_default.actions,
						children: [/* @__PURE__ */ (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.Button, {
							variant: "primary",
							onClick: run,
							disabled: checking || applying,
							icon: checking ? /* @__PURE__ */ (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.IconLoadingOutline16, {}) : /* @__PURE__ */ (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.IconRefreshOutline14, {}),
							children: checking ? t("checking") : t("check")
						}), showApply && /* @__PURE__ */ (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.Button, {
							variant: "primary",
							onClick: apply,
							icon: /* @__PURE__ */ (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.IconWarningOutline16, {}),
							children: t("apply")
						})]
					}),
					error !== null && /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
						className: UpdateSection_module_css_default.error,
						children: [
							t("error"),
							": ",
							error
						]
					}),
					applyFailed !== null && /* @__PURE__ */ (0, react_jsx_runtime.jsx)("div", {
						className: UpdateSection_module_css_default.error,
						children: applyFailed
					}),
					applying && /* @__PURE__ */ (0, react_jsx_runtime.jsx)("div", {
						className: UpdateSection_module_css_default.warn,
						children: t("applying")
					}),
					applying && /* @__PURE__ */ (0, react_jsx_runtime.jsx)("div", {
						className: UpdateSection_module_css_default.result,
						children: /* @__PURE__ */ (0, react_jsx_runtime.jsx)("div", {
							className: UpdateSection_module_css_default.line,
							children: t("applyStarted")
						})
					}),
					result !== null && !applying && /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
						className: UpdateSection_module_css_default.result,
						children: [
							/* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
								className: UpdateSection_module_css_default.line,
								children: [
									t("current"),
									": ",
									/* @__PURE__ */ (0, react_jsx_runtime.jsx)("b", { children: result.current })
								]
							}),
							/* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
								className: UpdateSection_module_css_default.line,
								children: [
									t("latest"),
									": ",
									/* @__PURE__ */ (0, react_jsx_runtime.jsx)("b", { children: result.latest })
								]
							}),
							result.status === "up-to-date" && /* @__PURE__ */ (0, react_jsx_runtime.jsx)("div", {
								className: UpdateSection_module_css_default.ok,
								children: t("upToDate")
							}),
							result.status === "update-available" && /* @__PURE__ */ (0, react_jsx_runtime.jsx)("div", {
								className: UpdateSection_module_css_default.warn,
								children: t("updateAvailable")
							}),
							result.status === "error" && /* @__PURE__ */ (0, react_jsx_runtime.jsx)("div", {
								className: UpdateSection_module_css_default.error,
								children: t("error")
							})
						]
					})
				]
			});
		}
		//#endregion
		//#region src/client/index.ts
		/**
		* dsh-update-check client: registers an "Update Check" settings section that
		* runs the host route and shows the result. Built by tsdown into the
		* __ModuleLoader__ factory bundle at client/client.js; the only externals are
		* the loader module table's react entries.
		*/
		const NS = "dsh-update-check";
		/** Primitives this bundle relies on. If the host resolves the primitives
		* module but lacks one, skip registration rather than blank the dialog. */
		const REQUIRED_PRIMITIVES = [
			"Button",
			"IconLoadingOutline16",
			"IconRefreshOutline14"
		];
		function missingPrimitives(mod, required = REQUIRED_PRIMITIVES) {
			return required.filter((name) => mod[name] === void 0);
		}
		const name = "dsh-update-check";
		const inject = ["slots", "locale"];
		function apply(ctx) {
			const gaps = missingPrimitives(_deepseek_ai_dsh_client_ui_primitives);
			if (gaps.length > 0) {
				console.warn(`[dsh-update-check] host ui-primitives missing ${gaps.join(", ")} — update section disabled (dsh web >= 0.1.0-rc.6 required)`);
				return;
			}
			ctx.effect(() => ctx.locale.register(NS, {
				zh,
				en
			}), "dsh-update-check: dictionaries");
			const t = ctx.locale.bind(NS);
			ctx.slots.inject("settings.section", () => ctx.slots.register({
				name: "settings.section",
				id: "dsh-update-check",
				order: 60,
				label: () => t("nav"),
				locale: NS,
				inject: () => ({ t })
			}, () => (0, react.createElement)(UpdateSection, { t })));
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