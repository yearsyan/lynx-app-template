/** Convert the native modules' error-string callback convention to a Promise. */
export function completeNativeCall(
  action: (callback: (error: string) => void) => void,
): Promise<void> {
  'background only';
  return new Promise((resolve, reject) => {
    action((error) => {
      if (error.length > 0) {
        reject(new Error(error));
      } else {
        resolve();
      }
    });
  });
}
