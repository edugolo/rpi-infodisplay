import {
  app,
  BrowserWindow,
  // dialog,
  // ipcMain,
  screen,
  // desktopCapturer,
  // session,
} from 'electron';
import * as sysInfo from 'systeminformation';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { readFile, writeFile } from 'node:fs/promises';
import { CronJob } from 'cron';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

let mainWindow = null;
let infoWindow = null;

// webFrame.setZoomFactor(1.5);

// Utility functions

const getSystemInfo = async () => {
  const si = await sysInfo.get({
    cpu: 'manufacturer, brand, vendor, family, model, revision',
    osInfo: 'platform, distro, release, codename, kernel, arch, serial', //'platform, release',
    system: 'manufacturer, model',
    networkInterfaces: 'iface, ifaceName, ip4, mac, type, default',
  });
  si.defaultNetworkInterface = si.networkInterfaces.find((iface) => {
    return iface.default === true;
  });
  delete si.networkInterfaces;
  return {
    serial: si.osInfo.serial,
    system: si,
  };
};

const systemInfo = await getSystemInfo();
const config = JSON.parse(await readFile('./config.json', 'utf-8'));

const actions = {
  saveProps: async (data) => {
    config.name = data.payload.props.name;
    config.location = data.payload.props.location;
    config.url = data.payload.props.url;
    config.zoomFactor = parseFloat(data.payload.props.zoomFactor);
    // JSON.parse(await readFile('./config.json', 'utf-8'));
    await writeFile('./config.json', JSON.stringify(config, null, 2), 'utf-8');

    mainWindow.loadURL(data.payload.props.url);
    mainWindow.webContents.setZoomFactor(
      parseFloat(data.payload.props.zoomFactor),
    );
    // Send device announcement
    (async () => {
      let result;
      try {
        result = await socket.invoke('devices/presence', {
          systemInfo,
          config,
        });
      } catch (error) {
        console.error(error);
      }
    })();
  },
  refresh: () => {
    mainWindow.reload();
  },
  toggleDevtools: () => {
    if (!mainWindow.webContents.isDevToolsOpened()) {
      mainWindow.webContents.openDevTools();
    } else {
      mainWindow.webContents.closeDevTools();
    }
  },
  showInfo: () => {
    showInfoWindow();
  },
  getScreenshot: async (data) => {
    console.log('getScreenshot', data);
    const image = await mainWindow.webContents.capturePage();
    try {
      // implement
    } catch (error) {
      console.log(error);
    }
  },
  ping: async (data) => {
    console.log('ping action', data);
    // const image = await mainWindow.webContents.capturePage();
    try {
      console.log(
        'ping confirmation',
        `devices/confirmationChannel:${data.messageId}`,
      );

      // implement
    } catch (error) {
      console.log(error);
    }
  },
};

// Shows Info for 10secs
const showInfoWindow = async () => {
  setInfoText(JSON.stringify({ config: config, device: systemInfo }, null, 2));
  infoWindow.show();
  setTimeout(() => {
    infoWindow.hide();
  }, 10000);
};

// Set text InfoWindow
const setInfoText = (text) => {
  infoWindow.webContents.send('setInfoText', text);
};

// Electron windows create functions
const createMainWindow = () => {
  const display = screen.getPrimaryDisplay();
  mainWindow = new BrowserWindow({
    x: display.bounds.x,
    y: display.bounds.y,
    width: display.size.width + 1,
    height: display.size.height,
    fullscreen: config.fullscreen ?? true,
    frame: config.frame ?? false,
    // focusable: false, // On Linux: false makes the window stop interacting with wm, so the window will always stay on top in all workspaces.
  });
  // debugger;
  // mainWindow.setFullScreen(true);
  mainWindow.loadURL(config.url ?? 'https://edugolo.be');

  // Hide cursor in webpage
  mainWindow.webContents.on('dom-ready', (event) => {
    let css = '* { cursor: none !important; }';
    mainWindow.webContents.insertCSS(css);
  });

  mainWindow.on('ready-to-show', () => {
    mainWindow.webContents.setZoomFactor(config.zoomFactor ?? 1);
  });
};

const createInfoWindow = () => {
  infoWindow = new BrowserWindow({
    parent: mainWindow,
    x: mainWindow.getBounds().x,
    y: mainWindow.getBounds().y,
    width: mainWindow.getBounds().width,
    height: mainWindow.getBounds().height,
    show: false,
    transparent: true,
    frame: false,
    backgroundColor: '#00FFFFFF',
    webPreferences: {
      preload: path.join(__dirname, 'preload.mjs'),
      nodeIntegrationInWorker: true,
      contextIsolation: true,
    },
  });
  infoWindow.loadFile(path.join(__dirname, 'info.html'));
  infoWindow.on('ready-to-show', () => {
    showInfoWindow();
  });
};

app.commandLine.appendSwitch('disable-gpu');

app.on('ready', async () => {
  createMainWindow();
  createInfoWindow();
  console.log('App ready');
});

app.on('before-quit', async (e) => {
  try {
    e.preventDefault();
    // implement rest api
    app.exit();
  } catch (error) {
    console.error(error);
  }
});
