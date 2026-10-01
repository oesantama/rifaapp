const { google } = require('googleapis');
const { Readable } = require('stream');
require('dotenv').config();

function getOAuth2Client() {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
  const refreshToken = process.env.GOOGLE_REFRESH_TOKEN;

  if (!clientId || !clientSecret || !refreshToken) {
    throw new Error('Faltan credenciales de Google Drive en las variables de entorno (.env).');
  }

  const oauth2Client = new google.auth.OAuth2(
    clientId,
    clientSecret,
    'https://developers.google.com/oauthplayground'
  );

  oauth2Client.setCredentials({ refresh_token: refreshToken });
  return oauth2Client;
}

function getDriveClient() {
  const auth = getOAuth2Client();
  return google.drive({ version: 'v3', auth });
}

/**
 * Renombra una carpeta o archivo en Google Drive.
 */
async function renameFolder(fileId, newName) {
  if (!fileId || !newName) return;
  try {
    const drive = getDriveClient();
    await drive.files.update({
      fileId: fileId,
      requestBody: {
        name: newName,
      },
    });
    console.log(`✅ Carpeta (${fileId}) renombrada a "${newName}" en Google Drive.`);
  } catch (error) {
    console.warn(`⚠️ Error al renombrar carpeta (${fileId}) en Drive:`, error.message);
  }
}

/**
 * Busca o crea una subcarpeta en Google Drive.
 */
async function findOrCreateSubfolder(folderName, parentFolderId) {
  const drive = getDriveClient();
  const safeName = folderName.replace(/'/g, "\\'");

  const query = `mimeType = 'application/vnd.google-apps.folder' and name = '${safeName}' and '${parentFolderId}' in parents and trashed = false`;

  const searchRes = await drive.files.list({
    q: query,
    fields: 'files(id, name)',
    spaces: 'drive',
  });

  if (searchRes.data.files && searchRes.data.files.length > 0) {
    return searchRes.data.files[0].id;
  }

  const fileMetadata = {
    name: folderName,
    mimeType: 'application/vnd.google-apps.folder',
    parents: [parentFolderId],
  };

  const createRes = await drive.files.create({
    resource: fileMetadata,
    fields: 'id',
  });

  return createRes.data.id;
}

/**
 * Obtiene o crea la carpeta de una Empresa en RifaApp_Storage
 */
async function getCompanyFolder(companyName, companyId) {
  const rootFolderId = process.env.GOOGLE_DRIVE_FOLDER_ID || 'root';
  const cleanCompName = (companyName || 'Empresa').replace(/[/\\?%*:|"<>]/g, '_').trim();
  const folderName = `${cleanCompName} (${companyId || 'general'})`;
  return await findOrCreateSubfolder(folderName, rootFolderId);
}

/**
 * Obtiene o crea la carpeta contenedora de Backups de la Base de Datos
 */
async function getBackupsFolder() {
  const rootFolderId = process.env.GOOGLE_DRIVE_FOLDER_ID || 'root';
  return await findOrCreateSubfolder('Backups_BaseDatos', rootFolderId);
}

/**
 * Obtiene o crea la estructura completa de carpetas:
 * RifaApp_Storage
 *  └── [Nombre Empresa] (id_empresa)
 *        └── [Nombre Rifa] (id_rifa)  <-- (renombrable automáticamente)
 *              ├── Afiche_2D/
 *              ├── Fondo_Boleta/
 *              └── Soportes_Abonos/
 */
async function getRaffleFolders(companyName, companyId, raffleTitle, raffleId, existingRaffleFolderId = null) {
  const companyFolderId = await getCompanyFolder(companyName, companyId);
  const cleanTitle = (raffleTitle || 'Rifa').replace(/[/\\?%*:|"<>]/g, '_').trim();
  const raffleFolderName = `${cleanTitle} (${raffleId || Date.now()})`;

  let raffleFolderId = existingRaffleFolderId;

  if (raffleFolderId) {
    await renameFolder(raffleFolderId, raffleFolderName);
  } else {
    raffleFolderId = await findOrCreateSubfolder(raffleFolderName, companyFolderId);
  }

  const [aficheFolderId, fondoBoletaFolderId, soportesFolderId] = await Promise.all([
    findOrCreateSubfolder('Afiche_2D', raffleFolderId),
    findOrCreateSubfolder('Fondo_Boleta', raffleFolderId),
    findOrCreateSubfolder('Soportes_Abonos', raffleFolderId),
  ]);

  return {
    companyFolderId,
    raffleFolderId,
    aficheFolderId,
    fondoBoletaFolderId,
    soportesFolderId,
  };
}

/**
 * Sube un buffer de imagen o JSON a Google Drive y le asigna permiso de lectura público.
 */
async function uploadFileToDrive({ buffer, filename, mimeType = 'image/jpeg', parentFolderId }) {
  const drive = getDriveClient();

  const fileMetadata = {
    name: filename,
    parents: [parentFolderId],
  };

  const media = {
    mimeType,
    body: Readable.from(buffer),
  };

  const file = await drive.files.create({
    resource: fileMetadata,
    media: media,
    fields: 'id, name, webViewLink, webContentLink',
  });

  const fileId = file.data.id;

  try {
    await drive.permissions.create({
      fileId,
      requestBody: {
        role: 'reader',
        type: 'anyone',
      },
    });
  } catch (e) {
    console.warn('⚠️ No se pudo asignar permiso público explícito al archivo:', e.message);
  }

  const directUrl = `https://lh3.googleusercontent.com/d/${fileId}=s1600`;
  const webViewUrl = `https://drive.google.com/uc?export=view&id=${fileId}`;

  return {
    fileId,
    filename,
    directUrl,
    webViewUrl,
    webContentLink: file.data.webContentLink,
  };
}

/**
 * Lista las copias de seguridad de la base de datos guardadas en Google Drive (carpeta Backups_BaseDatos).
 */
async function listDriveBackups() {
  try {
    const backupsFolderId = await getBackupsFolder();
    const drive = getDriveClient();
    const res = await drive.files.list({
      q: `'${backupsFolderId}' in parents and trashed = false`,
      fields: 'files(id, name, createdTime, size, webContentLink)',
      orderBy: 'createdTime desc',
      pageSize: 60,
    });
    return (res.data.files || []).map(f => ({
      id: `drive:${f.id}`,
      reason: f.name.replace(/^backup_rifamaster_/, '').replace(/_\d{4}-.*$/, '').replace(/\.json$/, ''),
      createdAt: f.createdTime,
      bytes: parseInt(f.size || '0'),
      location: 'drive',
      fileName: f.name,
      downloadUrl: f.webContentLink,
    }));
  } catch (e) {
    console.warn('⚠️ Error al listar copias de seguridad desde Google Drive:', e.message);
    return [];
  }
}

/**
 * Descarga el contenido JSON de un archivo de copia de seguridad en Google Drive.
 */
async function downloadDriveBackup(fileId) {
  const drive = getDriveClient();
  const res = await drive.files.get({ fileId, alt: 'media' }, { responseType: 'text' });
  return res.data;
}

/**
 * Elimina un archivo de Google Drive.
 */
async function deleteFileFromDrive(fileId) {
  if (!fileId) return false;
  try {
    const drive = getDriveClient();
    await drive.files.delete({ fileId });
    console.log(`✅ Archivo anterior (${fileId}) eliminado de Google Drive.`);
    return true;
  } catch (error) {
    if (error.code === 404) {
      console.log(`ℹ️ El archivo (${fileId}) ya no existía en Google Drive.`);
      return true;
    }
    console.error(`⚠️ Error al eliminar archivo (${fileId}) de Google Drive:`, error.message);
    return false;
  }
}

/**
 * Prueba de conexión a Google Drive.
 */
async function testDriveConnection() {
  const drive = getDriveClient();
  const rootFolderId = process.env.GOOGLE_DRIVE_FOLDER_ID || 'root';

  const folderInfo = await drive.files.get({
    fileId: rootFolderId,
    fields: 'id, name, mimeType',
  });

  return {
    status: 'ok',
    folderId: folderInfo.data.id,
    folderName: folderInfo.data.name,
  };
}

module.exports = {
  getDriveClient,
  renameFolder,
  findOrCreateSubfolder,
  getCompanyFolder,
  getBackupsFolder,
  getRaffleFolders,
  uploadFileToDrive,
  deleteFileFromDrive,
  listDriveBackups,
  downloadDriveBackup,
  testDriveConnection,
};
