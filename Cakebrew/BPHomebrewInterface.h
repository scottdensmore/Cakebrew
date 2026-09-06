//
//	BrewInterface.h
//	Cakebrew – The Homebrew GUI App for OS X
//
//	Created by Vincent Saluzzo on 06/12/11.
//	Copyright (c) 2014 Bruno Philipe. All rights reserved.
//
//	This program is free software: you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation, either version 3 of the License, or
//	(at your option) any later version.
//
//	This program is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import <Foundation/Foundation.h>

@class BPCleanupPreview;
@class BPAutoremovePreview;

@class BPService;
@class BPServiceDetails;
#import <Cocoa/Cocoa.h>
#import "BPFormula.h"

typedef NS_ENUM(NSInteger, BPHomebrewDiscoveryResult) {
	BPHomebrewDiscoveryUnknown,
	BPHomebrewDiscoveryAvailable,
	BPHomebrewDiscoveryMissing,
	BPHomebrewDiscoveryInvalidShell,
	BPHomebrewDiscoveryCheckFailed,
};

/// Where brew actually runs.
typedef NS_ENUM(NSInteger, BPBrewTransport) {
	/// In-process NSTask. The shipping (non-sandboxed) configuration.
	kBPBrewTransportDirect = 0,
	/// Through CakebrewHelper, which runs outside the app sandbox.
	kBPBrewTransportHelper = 1,
};

typedef NS_ENUM(NSInteger, BPListMode) {
	kBPListAll,
	kBPListInstalled,
	kBPListLeaves,
	kBPListOutdated,
	kBPListSearch, /* Don't call -[BPHomebrewInterface listMode:] with this parameter. */
	kBPListRepositories,
	kBPListPinned,
	kBPListInstalledCasks,
	kBPListOutdatedCasks,
	kBPListAllCasks
};

@protocol BPHomebrewInterfaceDelegate <NSObject>

/**
 *  Called when an operation has changed brew's state and the lists need
 *  refreshing.
 *
 *  @param shouldRebuildCatalogs `YES` only when the operation can change which
 *  packages *exist* (see +brewCommandChangesCatalogMembership:). Refetching the
 *  catalogs takes 80+ seconds cold, so an install or a pin must not ask for it.
 */
- (void)homebrewInterfaceDidUpdateFormulaeRebuildingCatalogs:(BOOL)shouldRebuildCatalogs;

/**
 *  Called if homebrew is not detected in the system.
 *
 *  @param yesOrNo `YES` if brew was not found.
 */
- (void)homebrewInterfaceShouldDisplayNoBrewMessage:(BOOL)yesOrNo;

@end

@interface BPHomebrewInterface : NSObject <BPFormulaDataProvider>

+ (instancetype)sharedInterface;
+ (instancetype)alloc __attribute__((unavailable("alloc not available, call sharedInterface instead")));
- (instancetype)init __attribute__((unavailable("init not available, call sharedInterface instead")));
+ (instancetype)new __attribute__((unavailable("new not available, call sharedInterface instead")));

/**
 *  The delegate object.
 */
@property (weak, nonatomic) id<BPHomebrewInterfaceDelegate> delegate;

/// Blocking discovery; the manager runs this off the main thread before lists.
/// Setting a delegate never executes a shell or displays UI.
- (BPHomebrewDiscoveryResult)discoverHomebrew;
+ (BPHomebrewDiscoveryResult)discoveryResultForOutput:(NSString *)output exitStatus:(int)status;
+ (NSURL *)installationURL;

#pragma mark - Operations with live data callback block

/**
 *  Terminates all running tasks
 */
- (void)cleanup;

/// Blocking, cancellation-owned direct commands. Helper transport fails closed.
- (BPAutoremovePreview *)previewAutoremoveWithProgress:(NSProgress *)progress;
- (BOOL)removeUnusedFormulae:(NSArray<NSString *> *)names progress:(NSProgress *)progress output:(void (^)(NSString *))output;

/// Targeted post-removal reads only. Nil means a failed/unsupported read, not
/// an empty list. Successful empty results are empty arrays. Direct transport only.
- (NSArray<BPFormula *> *)listModeForRemovalRefresh:(BPListMode)mode;
- (NSArray<BPService *> *)listServicesForRemovalRefresh;

/**
 *  Ends the operation the user is watching, over whichever transport is in use.
 *
 *  Only foreground operations are cancellable; list refreshes are not tracked,
 *  so cancelling an install cannot also abort a reload running beside it.
 */
- (void)cancelCurrentOperation;

/**
 *  Cancels every brew call currently running.
 *
 *  -cancelCurrentOperation covers the single operation task; a reload fans out
 *  ten concurrent list calls, and stopping it means stopping all of them.
 */
- (void)cancelAllRunningTasks;

/// Whether there is an operation to cancel, for enabling the button.
@property (readonly) BOOL hasCancellableOperation;

/**
 *  Update Homebrew.
 *
 *  @param block Data callback block. This block will be called with new data to be diplayed while the process runs.
 *
 *  @return `YES` if successful.
 */
- (BOOL)updateWithReturnBlock:(void (^)(NSString*))block;

/**
 *  Upgrade parameter formulae to the latest available version. Pass `nil` (or
 *  an empty array) to upgrade everything outdated.
 *
 *  @param formulae The list of formulae to be upgraded.
 *  @param block	Data callback block. This block will be called with new data to be diplayed while the process runs.
 *
 *  @return `YES` if successful.
 */
- (BOOL)upgradeFormulae:(NSArray*)formulae withReturnBlock:(void (^)(NSString*))block;

/**
 *  The argv for upgrading `formulae`, or for upgrading everything when the
 *  list is nil/empty.
 *
 *  Blank names are dropped rather than forwarded. Arguments reach brew as the
 *  shell's positional parameters, so an empty operand survives all the way to
 *  `brew upgrade ''`, which fails outright — see BPUpgradeArgumentsTests.
 */
+ (NSArray<NSString *> *)argumentsForUpgradingFormulae:(NSArray<NSString *> *)formulae;

/// As `argumentsForUpgradingFormulae:`, but for casks (adds `--cask`).
+ (NSArray<NSString *> *)argumentsForUpgradingCasks:(NSArray<NSString *> *)casks;

/**
 *  Whether a brew command can change which packages *exist* — as opposed to
 *  which are installed.
 *
 *  Only these justify refetching the full catalogs (`brew formulae` and
 *  `brew casks`), which AGENTS.md documents as 80+ seconds cold. Installing,
 *  uninstalling, upgrading, pinning and Doctor all leave catalog membership
 *  untouched. Unknown commands are treated as cheap, so a new operation that
 *  forgets to opt in cannot silently reintroduce the stall.
 */
+ (BOOL)brewCommandChangesCatalogMembership:(NSString *)command;

/**
 *  Upgrades casks (runs `brew upgrade --cask`).
 *
 *  @param casks The cask tokens to be upgraded.
 *  @param block Data callback block, called with new output while the process runs.
 *
 *  @return `YES` if successful.
 */
- (BOOL)upgradeCasks:(NSArray*)casks withReturnBlock:(void (^)(NSString*))block;

/**
 *  Install formula with options.
 *
 *  @param formula The formula to be installed.
 *  @param options Options for the formula installation (as explained in the info for a formula).
 *  @param block   Data callback block. This block will be called with new data to be diplayed while the process runs.
 *
 *  @return `YES` if successful.
 */
- (BOOL)installFormula:(NSString*)formula withOptions:(NSArray*)options andReturnBlock:(void (^)(NSString*output))block;

/**
 *  Installs a cask (runs `brew install --cask`). Casks take no install options.
 *
 *  @param cask The cask token to be installed.
 *  @param block Data callback block, called with new output while the process runs.
 *
 *  @return `YES` if successful.
 */
- (BOOL)installCask:(NSString*)cask withReturnBlock:(void (^)(NSString*))block;

/**
 *  Uninstalls a formula.
 *
 *  @param formula The formula to be uninstalled.
 *  @param block   Data callback block. This block will be called with new data to be diplayed while the process runs.
 *
 *  @return `YES` if successful.
 */
- (BOOL)uninstallFormula:(NSString*)formula withReturnBlock:(void (^)(NSString*))block;

/**
 *  Uninstalls a cask (runs `brew uninstall --cask`).
 *
 *  @param cask The cask token to be uninstalled.
 *  @param block Data callback block, called with new output while the process runs.
 *
 *  @return `YES` if successful.
 */
- (BOOL)uninstallCask:(NSString*)cask withReturnBlock:(void (^)(NSString*))block;

/**
 *  Uninstalls a cask, optionally running its zap stanza.
 *
 *  A plain uninstall removes the app bundle and deliberately leaves
 *  preferences, application support directories, launch agents and caches
 *  behind; `--zap` is Homebrew's answer to that.
 */
- (BOOL)uninstallCask:(NSString*)cask zap:(BOOL)zap withReturnBlock:(void (^)(NSString*))block;

/// The argv for uninstalling a cask. Blank tokens are dropped, for the same
/// reason as +argumentsForUpgradingFormulae:.
+ (NSArray<NSString *> *)argumentsForUninstallingCask:(NSString *)cask zap:(BOOL)zap;

/**
 *  Taps a repo.
 *
 *  @param repository The repo to be tapped.
 *  @param block Data callback block. This block will be called with new data to be diplayed while the process runs.
 *
 *  @return `YES` if successful.
 */
- (BOOL)tapRepository:(NSString*)repository withReturnsBlock:(void (^)(NSString*))block;

/**
 *  Untaps a repo.
 *
 *  @param repository The repo to be untapped.
 *  @param block Data callback block. This block will be called with new data to be diplayed while the process runs.
 *
 *  @return `YES` if successful.
 */
- (BOOL)untapRepository:(NSString*)repository withReturnsBlock:(void (^)(NSString*))block;

/**
 *  Pins a formula, holding it at its installed version so upgrades skip it.
 *
 *  @param formula The formula to pin.
 *  @param block Data callback block, called with new output while the process runs.
 *
 *  @return `YES` if successful.
 */
- (BOOL)pinFormula:(NSString*)formula withReturnBlock:(void (^)(NSString*))block;

/**
 *  Unpins a previously pinned formula so it can be upgraded again.
 *
 *  @param formula The formula to unpin.
 *  @param block Data callback block, called with new output while the process runs.
 *
 *  @return `YES` if successful.
 */
- (BOOL)unpinFormula:(NSString*)formula withReturnBlock:(void (^)(NSString*))block;

/**
 *  Runs Homebrew cleanup tool.
 *
 *  @param block Data callback block. This block will be called with new data to be diplayed while the process runs.
 *
 *  @return `YES` if successful.
 */
- (BOOL)runCleanupWithReturnBlock:(void (^)(NSString*output))block;

/// The arguments for the cleanup preview. `--dry-run` makes brew report what it
/// would delete without deleting it.
+ (NSArray<NSString *> *)argumentsForCleanupDryRun;

/**
 *  Asks brew what a cleanup would remove, without removing anything.
 *
 *  Blocking — brew has to walk the cache and the Cellar — so call it off the
 *  main thread. Never returns nil; a failed or unreadable run is an empty
 *  preview, which reads as "nothing to clean" rather than inventing a number.
 */
- (BPCleanupPreview *)previewCleanup;

/**
 *  Runs Homebrew doctor tool.
 *
 *  @param block Data callback block. This block will be called with new data to be diplayed while the process runs.
 *
 *  @return `YES` if successful.
 */
- (BOOL)runDoctorWithReturnBlock:(void (^)(NSString*))block;

/**
 *  Runs Homebrew bundle dump tool. Will request instalation of Homebrew-Bundle tap if it is not already tapped.
 *
 *  @param path The path where to export the dump file.
 *
 *  @return `nil` on success (no output), or the error in case something goes wrong.
 */
- (NSError*)runBrewExportToolWithPath:(NSString*)path;

/// Blocking, direct transport only; the token cancels this exact import task.
- (BOOL)runBrewImportToolWithPath:(NSString *)path progress:(NSProgress *)progress withReturnsBlock:(void (^)(NSString *))block;

/**
 *  Runs Homebrew bundle import tool. Will request instalation of Homebrew-Bundle tap if it is not already tapped.
 *
 *  @param path The path where to export the dump file.
 *  @param block Data callback block. This block will be called with new data to be diplayed while the process runs.
 *
 *  @return `YES` on success, `NO` otherwise.
 */
- (BOOL)runBrewImportToolWithPath:(NSString*)path withReturnsBlock:(void (^)(NSString *))block;

#pragma mark - Operations that return on finish

/**
 *  Lists all formulae that fits the description of the parameter mode.
 *
 *  @param mode All, Installed, Leaves, Outdated, etc.
 *
 *  @return List of BPFormula objects.
 */
/// Selected automatically at startup; overridable for testing.
@property (assign) BPBrewTransport brewTransport;

/// The transport a build should use given whether it is sandboxed.
+ (BPBrewTransport)defaultTransportWhenSandboxed:(BOOL)sandboxed;

/// Whether this process is running inside the App Sandbox.
+ (BOOL)isRunningSandboxed;

- (NSArray*)listMode:(BPListMode)mode;

/**
 *  Whether `name` is a well-formed Homebrew tap name (owner/repo). Rejects
 *  whitespace and shell metacharacters — defense in depth for the free-text
 *  Tap field. Surrounding whitespace is trimmed before checking.
 */
+ (BOOL)isValidTapName:(NSString *)name;

/**
 *  Executes `brew info` for parameter formula name.
 *
 *  @param name The name of the formula.
 *
 *  @return The information for the parameter formula as output by Homebrew.
 */
- (NSString *)informationForFormulaName:(NSString *)name;

/**
 *  Returns `brew info --cask` output for a cask token.
 *
 *  @param name The cask token.
 *
 *  @return The raw `brew info --cask` output.
 */
- (NSString *)informationForCaskName:(NSString *)name;

/**
 *  Lists background services (`brew services list --json`), parsed.
 *
 *  @return The services, or an empty array when there are none / on error.
 */
- (NSArray<BPService *> *)listServices;

/// Blocking read-only lookup; call from a background queue. Keeps raw errors.
- (BPServiceDetails *)serviceDetailsForName:(NSString *)name;

/**
 *  Starts a service (`brew services start`).
 */
- (BOOL)startService:(NSString*)name withReturnBlock:(void (^)(NSString*))block;

/**
 *  Stops a service (`brew services stop`).
 */
- (BOOL)stopService:(NSString*)name withReturnBlock:(void (^)(NSString*))block;

/**
 *  Restarts a service (`brew services restart`).
 */
- (BOOL)restartService:(NSString*)name withReturnBlock:(void (^)(NSString*))block;

/**
 *  Executes `brew uses` for parameter formula name.
 *
 *  @param name The name of the formula.
 *  @param onlyInstalled If should only show installed dependents.
 *
 *  @return The list of dependents for the parameter formula as output by Homebrew.
 */
- (NSString *)dependantsForFormulaName:(NSString *)name onlyInstalled:(BOOL)onlyInstalled;

#pragma mark – Utilities

/**
 *
 *  Checks if there is any non-terminated task in queue
 *
 *  @return YES if there is any task in background queue. No if the queue is empty
 *
 */
- (BOOL)isRunningBackgroundTask;

@end
