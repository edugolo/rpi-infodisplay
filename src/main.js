import { app, BrowserWindow, screen } from 'electron';
import * as sysInfo from 'systeminformation';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { readFile, writeFile } from 'node:fs/promises';


const __dirname = path.dirname(fileURLToPath(import.meta.url));

let mainWindow = null;
let infoWindow = null;

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
    await writeFile('./config.json', JSON.stringify(config, null, 2), 'utf-8');

    mainWindow.loadURL(data.payload.props.url);
    mainWindow.webContents.setZoomFactor(
      parseFloat(data.payload.props.zoomFactor),
    );
    // TODO: Implement REST API call for device presence
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
  getScreenshot: async () => {
    const image = await mainWindow.webContents.capturePage();
    // TODO: Implement REST API call to upload screenshot
    return image;
  },
  ping: async () => {
    // TODO: Implement REST API ping confirmation
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
  });

  mainWindow.loadURL(config.url ?? 'https://edugo.be');

  // Hide cursor in webpage
  mainWindow.webContents.on('dom-ready', () => {
    const css = '* { cursor: none !important; }';
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
      preload: path.join(__dirname, 'preload.js'),
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

app.whenReady().then(() => {
  createMainWindow();
  createInfoWindow();
  console.log('App ready');
});

app.on('before-quit', () => {
  // TODO: Implement REST API call for device disconnect
  app.exit();
});
