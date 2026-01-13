import { contextBridge, ipcRenderer } from 'electron/renderer';

contextBridge.exposeInMainWorld('electronAPI', {
  setInfoText: (callback) =>
    ipcRenderer.on('setInfoText', (_event, value) => callback(value)),
});
